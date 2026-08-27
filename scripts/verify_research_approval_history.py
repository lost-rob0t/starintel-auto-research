#!/usr/bin/env python3
"""Verify approval-migration history without freezing later research edits."""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path
from typing import Sequence

from research_approval_migration import (
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


def _first_canonical_snapshot(
    root: Path,
    base_commit: str,
    relative_path: Path,
    source: str,
) -> str:
    _, _, _, source_metadata = _split_header(source)
    if _canonical_values(source_metadata) is not None:
        return source

    commits = _git(
        root,
        ["rev-list", "--reverse", f"{base_commit}..HEAD", "--", relative_path.as_posix()],
    ).splitlines()
    for commit in commits:
        try:
            candidate = _show(root, commit, relative_path)
        except MigrationError:
            continue
        _, _, _, metadata = _split_header(candidate)
        if _canonical_values(metadata) is not None:
            return candidate

    raise MigrationError(
        f"{relative_path}: cannot find first canonical approval snapshot after {base_commit}"
    )


def verify_file(root: Path, path: Path) -> None:
    relative_path = path.relative_to(root)
    current_text = path.read_text(encoding="utf-8")
    _, _, _, current_metadata_raw = _split_header(current_text)
    current_metadata = _metadata_values(current_metadata_raw)
    if _canonical_values(current_metadata_raw) is None:
        raise MigrationError(f"{relative_path}: canonical approval metadata is missing")

    base_commit = current_metadata.get("approval_base_commit", "")
    base_blob = current_metadata.get("approval_base_blob", "")
    if not base_commit or not base_blob:
        raise MigrationError(f"{relative_path}: approval base provenance is incomplete")

    source = _show(root, base_commit, relative_path)
    if _blob_sha(root, source) != base_blob:
        raise MigrationError(
            f"{relative_path}: recorded approval base blob does not match source"
        )

    migrated = _first_canonical_snapshot(root, base_commit, relative_path, source)
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
