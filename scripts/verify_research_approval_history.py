#!/usr/bin/env python3
"""Verify approval-migration history without freezing later research edits."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from typing import Sequence

from research_approval_migration import (
    CANONICAL_SCHEMA,
    MigrationError,
    _canonical_values,
    _metadata_values,
    _split_header,
    discover_research_files,
)


def _git(root: Path, args: Sequence[str], *, input_text: str | None = None) -> str:
    try:
        result = subprocess.run(
            ["git", *args],
            cwd=root,
            text=True,
            input=input_text,
            capture_output=True,
            check=True,
        )
    except (OSError, subprocess.CalledProcessError) as error:
        detail = getattr(error, "stderr", "") or str(error)
        raise MigrationError(f"git {' '.join(args)} failed: {detail.strip()}") from error
    return result.stdout


def _show(root: Path, commit: str, relative_path: Path) -> str:
    return _git(root, ["show", f"{commit}:{relative_path.as_posix()}"])


def _blob_sha(root: Path, text: str) -> str:
    return _git(root, ["hash-object", "--stdin"], input_text=text).strip()


def _commit_exists(root: Path, commit: str) -> None:
    _git(root, ["rev-parse", "--verify", f"{commit}^{{commit}}"])


def _commit_exists_bool(root: Path, commit: str) -> bool:
    result = subprocess.run(
        ["git", "rev-parse", "--verify", f"{commit}^{{commit}}"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def _path_exists_at_commit(root: Path, commit: str, relative_path: Path) -> bool:
    _commit_exists(root, commit)
    result = subprocess.run(
        ["git", "cat-file", "-e", f"{commit}:{relative_path.as_posix()}"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    return result.returncode == 0


def _unique_blob_path_at_commit(root: Path, commit: str, blob_sha: str) -> Path:
    entries = _git(
        root,
        ["ls-tree", "-r", "--full-tree", commit, "--", "roam/research"],
    ).splitlines()
    matches: list[Path] = []
    for entry in entries:
        try:
            metadata, path_text = entry.split("\t", 1)
            _, object_type, object_sha = metadata.split()
        except ValueError as error:
            raise MigrationError(
                f"cannot parse git tree entry while resolving approval base: {entry!r}"
            ) from error
        if object_type == "blob" and object_sha == blob_sha:
            matches.append(Path(path_text))

    if not matches:
        raise MigrationError(
            f"approval base blob {blob_sha} is not present under roam/research at {commit}"
        )
    if len(matches) != 1:
        rendered = ", ".join(path.as_posix() for path in matches)
        raise MigrationError(
            f"approval base blob {blob_sha} is ambiguous at {commit}: {rendered}"
        )
    return matches[0]


def _resolve_base_source(
    root: Path,
    base_commit: str,
    relative_path: Path,
    base_blob: str,
) -> tuple[Path, str]:
    if _path_exists_at_commit(root, base_commit, relative_path):
        source_path = relative_path
    else:
        # Canonical IDs may be repaired by renaming a document after approval
        # migration.  Provenance is content-addressed, so recover the historical
        # source only when the recorded blob identifies exactly one research
        # file in the recorded base commit.  This follows a rename without
        # permitting fuzzy filename guesses or arbitrary path substitution.
        source_path = _unique_blob_path_at_commit(root, base_commit, base_blob)

    source = _show(root, base_commit, source_path)
    if _blob_sha(root, source) != base_blob:
        raise MigrationError(
            f"{relative_path}: recorded approval base blob does not match source"
        )
    return source_path, source


def _is_adard_canonical(metadata: dict[str, list[str]]) -> bool:
    values = _metadata_values(metadata)
    if values.get("approval_schema") != CANONICAL_SCHEMA:
        return False
    return _canonical_values(metadata) is not None


def _first_canonical_history_snapshot(
    root: Path,
    base_commit: str | None,
    relative_path: Path,
) -> tuple[str, str]:
    revision = "HEAD" if base_commit is None else f"{base_commit}..HEAD"
    commits = _git(
        root,
        ["rev-list", "--reverse", revision, "--", relative_path.as_posix()],
    ).splitlines()
    for commit in commits:
        try:
            candidate = _show(root, commit, relative_path)
        except MigrationError:
            continue
        _, _, _, metadata = _split_header(candidate)
        try:
            if _is_adard_canonical(metadata):
                return commit, candidate
        except MigrationError as error:
            raise MigrationError(f"{relative_path}@{commit}: {error}") from error

    anchor = "repository history" if base_commit is None else f"after {base_commit}"
    raise MigrationError(
        f"{relative_path}: cannot find first canonical approval snapshot in {anchor}"
    )


def _first_canonical_snapshot(
    root: Path,
    base_commit: str | None,
    relative_path: Path,
    source: str | None,
) -> str:
    if source is not None:
        _, _, _, source_metadata = _split_header(source)
        try:
            if _is_adard_canonical(source_metadata):
                return source
        except MigrationError:
            # The exact, blob-verified base may itself be the malformed partial
            # migration being repaired.  Treat only that anchored source as
            # pre-canonical and require the first later snapshot to be fully
            # canonical.  Malformed snapshots encountered after the base still
            # fail closed below.
            pass

    _, candidate = _first_canonical_history_snapshot(root, base_commit, relative_path)
    return candidate


def _verify_canonical_born(
    root: Path,
    relative_path: Path,
    base_commit: str,
    base_blob: str,
) -> None:
    if base_blob != "NONE":
        raise MigrationError(
            f"{relative_path}: approval base commit NONE requires approval base blob NONE"
        )

    anchor = None if base_commit == "NONE" else base_commit
    if anchor is not None and _path_exists_at_commit(root, anchor, relative_path):
        raise MigrationError(
            f"{relative_path}: approval base blob is NONE but path exists at base {anchor}"
        )

    first_commit, first = _first_canonical_history_snapshot(root, anchor, relative_path)
    _, _, _, first_metadata_raw = _split_header(first)
    first_metadata = _metadata_values(first_metadata_raw)
    first_base_commit = first_metadata.get("approval_base_commit", "")
    first_base_blob = first_metadata.get("approval_base_blob", "")

    if first_base_blob != "NONE":
        raise MigrationError(
            f"{relative_path}: canonical-born approval base blob changed after creation"
        )
    if first_base_commit == base_commit:
        return

    # Legacy repair path: a small number of canonical-born records accidentally
    # stored a commit SHA from the source repository they were researching as
    # approval provenance.  Permit correcting that foreign SHA only when the
    # replacement anchor is provably the parent of the first canonical commit
    # and the path was absent there.  Existing in-repository anchors remain
    # immutable and cannot use this escape hatch.
    if base_commit == "NONE" or not first_base_commit:
        raise MigrationError(
            f"{relative_path}: canonical-born approval base commit changed after creation"
        )
    if _commit_exists_bool(root, first_base_commit):
        raise MigrationError(
            f"{relative_path}: canonical-born approval base commit changed after creation"
        )

    lineage = _git(root, ["rev-list", "--parents", "-n", "1", first_commit]).split()
    parents = lineage[1:]
    if base_commit not in parents:
        raise MigrationError(
            f"{relative_path}: corrected approval base must be a parent of first canonical commit"
        )


def verify_file(root: Path, path: Path) -> None:
    relative_path = path.relative_to(root)
    current_text = path.read_text(encoding="utf-8")
    _, _, _, current_metadata_raw = _split_header(current_text)
    current_metadata = _metadata_values(current_metadata_raw)
    try:
        canonical = _canonical_values(current_metadata_raw)
    except MigrationError as error:
        raise MigrationError(f"{relative_path}: {error}") from error
    if canonical is None:
        raise MigrationError(f"{relative_path}: canonical approval metadata is missing")

    base_commit = current_metadata.get("approval_base_commit", "")
    base_blob = current_metadata.get("approval_base_blob", "")
    if not base_commit or not base_blob:
        raise MigrationError(f"{relative_path}: approval base provenance is incomplete")

    if base_commit == "NONE" or base_blob == "NONE":
        _verify_canonical_born(root, relative_path, base_commit, base_blob)
        return

    source_path, source = _resolve_base_source(
        root,
        base_commit,
        relative_path,
        base_blob,
    )

    # Verify the migration on the path that actually held the recorded base
    # blob.  Later canonical-ID/path repairs are allowed after that first
    # canonical snapshot, just like later research-body edits are allowed.
    migrated = _first_canonical_snapshot(root, base_commit, source_path, source)
    _, _, source_body, source_metadata = _split_header(source)
    _, _, migrated_body, migrated_metadata = _split_header(migrated)

    if source_body != migrated_body:
        raise MigrationError(f"{relative_path}: research body changed during migration")

    source_status = source_metadata.get("status", [""])[0]
    migrated_status = migrated_metadata.get("status", [""])[0]
    if source_status != migrated_status:
        raise MigrationError(f"{relative_path}: lifecycle keyword changed during migration")


def verify_repository(root: Path) -> int:
    checked = 0
    for path in discover_research_files(root):
        verify_file(root, path)
        checked += 1
    return checked


def main() -> int:
    root = Path.cwd().resolve()
    try:
        checked = verify_repository(root)
    except (OSError, UnicodeError, MigrationError) as error:
        print(f"research_approval_history=FAIL error={error}", file=sys.stderr)
        return 1
    print(f"research_approval_history=PASS checked={checked}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())