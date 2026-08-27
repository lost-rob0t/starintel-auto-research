#!/usr/bin/env python3
"""Migrate legacy research decisions to canonical approval metadata.

The migration deliberately treats lifecycle keywords and research approval as
separate facts.  Only explicit research-conclusion evidence can produce an
APPROVED or REJECTED decision; every other eligible record is conservatively
left PENDING with an explanation in its migration evidence.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Sequence

CANONICAL_SCHEMA = "adard.research-approval.v1"
CANONICAL_FIELDS = (
    "approval_schema",
    "approval_state",
    "approval_actor",
    "approval_evidence",
    "approval_base_commit",
    "approval_base_blob",
    "approval_decided_at",
)
APPROVAL_STATES = frozenset({"PENDING", "APPROVED", "REJECTED"})
AUXILIARY_FILENAMES = frozenset({"index.org", "sources.org", "search-log.org"})
KEYWORD_RE = re.compile(r"^\s*#\+([A-Za-z0-9_-]+):\s*(.*?)\s*$", re.IGNORECASE)
DATE_RE = re.compile(r"\b(20\d{2}-\d{2}-\d{2})\b")
TABLE_RE = re.compile(r"^\s*\|.*\|\s*$")


class MigrationError(ValueError):
    """Raised when a document cannot be migrated without inventing approval."""


@dataclass(frozen=True, slots=True)
class ApprovalSignal:
    state: str
    actor: str
    evidence: str
    decided_at: str
    source: str


@dataclass(frozen=True, slots=True)
class MigrationResult:
    relative_path: Path
    text: str
    body: str
    lifecycle: str
    approval_state: str
    approval_actor: str
    approval_evidence: str
    approval_decided_at: str
    changed: bool
    canonical_before: bool
    ambiguous: tuple[str, ...] = ()


def discover_research_files(root: Path) -> list[Path]:
    """Return the same durable research scope consumed by the queue."""

    research_root = root / "roam" / "research"
    if not research_root.is_dir():
        raise MigrationError(f"missing research root: {research_root}")
    return sorted(
        path
        for path in research_root.rglob("*.org")
        if path.is_file() and path.name.lower() not in AUXILIARY_FILENAMES
    )


def _split_header(text: str) -> tuple[str, str, str, dict[str, list[str]]]:
    """Split source metadata from content while retaining content bytes."""

    lines = text.splitlines(keepends=True)
    index = 0
    if lines and lines[0].strip().upper() == ":PROPERTIES:":
        index = 1
        while index < len(lines):
            if lines[index].strip().upper() == ":END:":
                index += 1
                break
            index += 1

    metadata: dict[str, list[str]] = {}
    while index < len(lines):
        match = KEYWORD_RE.match(lines[index])
        if match:
            metadata.setdefault(match.group(1).lower(), []).append(match.group(2).strip())
            index += 1
            continue
        if not lines[index].strip():
            index += 1
            continue
        break

    body_start = index
    # Keep the existing metadata/content separator outside the body.  The
    # actual Org content, including every byte after its first nonblank line,
    # is copied unchanged.
    prefix_end = body_start
    while prefix_end and not lines[prefix_end - 1].strip():
        prefix_end -= 1
    prefix = "".join(lines[:prefix_end])
    separator = "".join(lines[prefix_end:body_start])
    body = "".join(lines[body_start:])
    return prefix, separator, body, metadata


def _metadata_values(metadata: dict[str, list[str]]) -> dict[str, str]:
    return {key: values[0] for key, values in metadata.items() if values}


def _table_cells(line: str) -> list[str]:
    cells = [cell.strip() for cell in line.strip()[1:-1].split("|")]
    return [re.sub(r"\s+", " ", cell) for cell in cells]


def _is_separator(cells: Sequence[str]) -> bool:
    nonempty = [cell for cell in cells if cell]
    return bool(nonempty) and all(set(cell) <= {"-", "+", ":"} for cell in nonempty)


def _tables(text: str) -> Iterable[tuple[list[str], list[list[str]]]]:
    lines = text.splitlines()
    index = 0
    while index < len(lines):
        if not TABLE_RE.match(lines[index]):
            index += 1
            continue
        raw: list[list[str]] = []
        while index < len(lines) and TABLE_RE.match(lines[index]):
            cells = _table_cells(lines[index])
            if not _is_separator(cells):
                raw.append(cells)
            index += 1
        if raw:
            yield raw[0], raw[1:]


def _one_line(value: str) -> str:
    return re.sub(r"\s+", " ", value).strip()


def _actor(authority: str, evidence: str) -> str:
    combined = f"{authority} {evidence}".lower()
    if "nsaspy" in combined:
        return "nsaspy"
    if any(word in combined for word in ("operator", "project owner", "user approval", "user-approved")):
        return "operator"
    if "human" in combined:
        return "human"
    return "human-reviewer"


def _date(value: str) -> str:
    dates = DATE_RE.findall(value)
    return max(dates) if dates else "NOT RECORDED"


def _research_area(area: str) -> bool:
    normalized = _one_line(area).lower()
    return bool(
        re.fullmatch(
            r"research(?: basis| scope| direction| conclusion| findings?| decision| recommendation)?|client library stack",
            normalized,
        )
    )


def _legacy_yes_is_research(description: str) -> bool:
    normalized = _one_line(description).lower()
    # A project identifier such as ADAR-RESEARCH-001 is not itself evidence
    # that the human approved the research conclusion.
    normalized = re.sub(r"\b[a-z]+-(?:research|approval)-\d+[a-z-]*\b", "", normalized)
    if not normalized:
        return False
    research_terms = (
        "research",
        "finding",
        "conclusion",
        "scope",
        "basis",
        "analysis",
        "selection",
        "landscape",
        "comparison",
        "direction",
        "decision",
        "audit",
        "comparison",
        "compare",
        "investigation",
        "language",
        "model",
        "eligibility",
        "scope",
        "evaluate",
    )
    design_only = ("design", "implementation", "architecture", "prototype")
    if not any(term in normalized for term in research_terms):
        return False
    if any(term in normalized for term in design_only) and not any(
        term in normalized for term in (
            "research",
            "finding",
            "conclusion",
            "comparison",
            "compare",
            "language approval",
        )
    ):
        return False
    return True


def _signals(text: str) -> tuple[list[ApprovalSignal], list[str]]:
    signals: list[ApprovalSignal] = []
    ambiguous: list[str] = []

    for header, rows in _tables(text):
        normalized_header = [cell.lower() for cell in header]
        if len(normalized_header) >= 3 and normalized_header[0] == "approval area" and "state" in normalized_header:
            state_index = normalized_header.index("state")
            evidence_index = normalized_header.index("evidence reference") if "evidence reference" in normalized_header else 4
            authority_index = normalized_header.index("required authority") if "required authority" in normalized_header else 1
            for row in rows:
                if len(row) <= state_index:
                    ambiguous.append("malformed Approval Table row")
                    continue
                area = row[0] if row else ""
                if not _research_area(area):
                    continue
                state = row[state_index].upper()
                evidence = row[evidence_index] if len(row) > evidence_index else ""
                authority = row[authority_index] if len(row) > authority_index else ""
                if state not in {"APPROVED", "REJECTED"}:
                    continue
                if not evidence:
                    ambiguous.append(f"{area}: {state} has no evidence reference")
                    continue
                signals.append(
                    ApprovalSignal(
                        state=state,
                        actor=_actor(authority, evidence),
                        evidence=f"legacy Approval Table: {area}; {_one_line(evidence)}",
                        decided_at=_date(evidence),
                        source=f"Approval Table/{area}",
                    )
                )

        if (
            any("did " in cell and "approve" in cell for cell in normalized_header)
            and "version" in normalized_header
        ):
            approve_index = next(
                index for index, cell in enumerate(normalized_header) if "approve" in cell
            )
            date_index = normalized_header.index("date") if "date" in normalized_header else None
            description_index = (
                normalized_header.index("description of change")
                if "description of change" in normalized_header
                else 2
            )
            legacy_candidates: list[ApprovalSignal | None] = []
            for row in rows:
                if len(row) <= approve_index:
                    continue
                decision = row[approve_index].strip().lower()
                description = row[description_index] if len(row) > description_index else ""
                if not _legacy_yes_is_research(description):
                    continue
                date_value = row[date_index] if date_index is not None and len(row) > date_index else ""
                if decision in {"yes", "approved"}:
                    legacy_candidates.append(
                        ApprovalSignal(
                            state="APPROVED",
                            actor="nsaspy",
                            evidence=(
                                "legacy human approval table: "
                                f"{_one_line(description)}"
                            ),
                            decided_at=_date(date_value or description),
                            source="legacy human approval table",
                        )
                    )
                elif decision in {"rejected", "denied"}:
                    legacy_candidates.append(
                        ApprovalSignal(
                            state="REJECTED",
                            actor="nsaspy",
                            evidence=(
                                "legacy human rejection table: "
                                f"{_one_line(description)}"
                            ),
                            decided_at=_date(date_value or description),
                            source="legacy human approval table",
                        )
                    )
                elif decision in {"no", "pending", "pending review"}:
                    # "No" in the old table means not approved yet, not a
                    # human rejection.  It supersedes an earlier Yes row.
                    legacy_candidates.append(None)
            if legacy_candidates and legacy_candidates[-1] is not None:
                signals.append(legacy_candidates[-1])

    # A prose approval that is explicitly about a design or implementation is
    # intentionally not promoted to research approval.  It is reported as an
    # ambiguity so the resulting PENDING metadata explains the decision.
    for line in text.splitlines():
        lower = line.lower()
        if "approv" not in lower:
            continue
        if any(
            term in lower
            for term in (
                "approval activates implementation",
                "approval of the linked design",
                "approve the design",
            )
        ):
            ambiguous.append("prose approval concerns design or implementation, not a research conclusion")

    return signals, sorted(set(ambiguous))


def _canonical_values(metadata: dict[str, list[str]]) -> dict[str, str] | None:
    present = {field: metadata.get(field, []) for field in CANONICAL_FIELDS}
    count = sum(bool(values) for values in present.values())
    if not count:
        return None
    if count != len(CANONICAL_FIELDS) or any(len(values) != 1 for values in present.values()):
        raise MigrationError("partial or duplicate canonical approval metadata")
    values = {field: present[field][0].strip() for field in CANONICAL_FIELDS}
    if values["approval_schema"] != CANONICAL_SCHEMA:
        raise MigrationError(f"unsupported approval schema: {values['approval_schema']}")
    if values["approval_state"] not in APPROVAL_STATES:
        raise MigrationError(f"invalid canonical approval state: {values['approval_state']}")
    for field in ("approval_actor", "approval_evidence", "approval_base_commit", "approval_base_blob"):
        if not values[field]:
            raise MigrationError(f"canonical {field} is empty")
    return values


def _canonical_header(prefix: str, separator: str, values: dict[str, str], body: str) -> str:
    match = re.search(r"\r?\n", prefix)
    newline = match.group(0) if match else "\n"
    fields = "".join(
        f"#+{field}:" + (f" {values[field]}" if values[field] else "") + newline
        for field in CANONICAL_FIELDS
    )
    lines = prefix.splitlines(keepends=True)
    canonical_lines = set(CANONICAL_FIELDS)
    lines = [
        line
        for line in lines
        if not (
            (keyword := KEYWORD_RE.match(line))
            and keyword.group(1).lower() in canonical_lines
        )
    ]
    status_index = next(
        (
            index
            for index, line in enumerate(lines)
            if (keyword := KEYWORD_RE.match(line))
            and keyword.group(1).lower() == "status"
        ),
        None,
    )
    if status_index is None:
        lines.extend(fields)
    else:
        lines[status_index + 1 : status_index + 1] = fields
    rebuilt = "".join(lines)
    if rebuilt and not rebuilt.endswith(("\n", "\r")):
        rebuilt += newline
    return rebuilt + separator + body


def migrate_document(
    text: str,
    *,
    relative_path: Path,
    base_commit: str,
    base_blob: str,
    normalize: bool = False,
) -> MigrationResult:
    prefix, separator, body, metadata = _split_header(text)
    values = _canonical_values(metadata)
    lifecycle = _metadata_values(metadata).get("status", "").strip().upper() or "MISSING"

    if values is not None:
        normalized_values = dict(values)
        if normalized_values["approval_state"] == "PENDING" and not normalized_values["approval_decided_at"]:
            normalized_values["approval_decided_at"] = "NONE"
        normalized = (
            _canonical_header(prefix, separator, normalized_values, body) if normalize else text
        )
        return MigrationResult(
            relative_path=relative_path,
            text=normalized,
            body=body,
            lifecycle=lifecycle,
            approval_state=values["approval_state"],
            approval_actor=values["approval_actor"],
            approval_evidence=values["approval_evidence"],
            approval_decided_at=normalized_values["approval_decided_at"],
            changed=normalized != text,
            canonical_before=True,
        )

    signals, ambiguous = _signals(text)
    states = {signal.state for signal in signals}
    if len(states) > 1:
        details = "; ".join(f"{signal.source}={signal.state}" for signal in signals)
        raise MigrationError(f"contradictory research approval evidence: {details}")

    if signals:
        signal = signals[-1]
        state = signal.state
        actor = signal.actor
        evidence = signal.evidence
        decided_at = signal.decided_at
    else:
        state = "PENDING"
        actor = "research-approval-migration"
        if ambiguous:
            reason = "; ".join(ambiguous)
            evidence = (
                "migration: ambiguous legacy approval evidence ("
                f"{reason}); left PENDING; lifecycle is not research approval"
            )
        else:
            evidence = (
                "migration: no explicit human research-conclusion decision; "
                f"legacy lifecycle {lifecycle} is not research approval"
            )
        decided_at = "NONE"

    canonical = {
        "approval_schema": CANONICAL_SCHEMA,
        "approval_state": state,
        "approval_actor": actor,
        "approval_evidence": _one_line(evidence),
        "approval_base_commit": base_commit,
        "approval_base_blob": base_blob,
        "approval_decided_at": decided_at,
    }
    migrated = _canonical_header(prefix, separator, canonical, body)
    return MigrationResult(
        relative_path=relative_path,
        text=migrated,
        body=body,
        lifecycle=lifecycle,
        approval_state=state,
        approval_actor=actor,
        approval_evidence=canonical["approval_evidence"],
        approval_decided_at=decided_at,
        changed=migrated != text,
        canonical_before=False,
        ambiguous=tuple(ambiguous),
    )


def _git_value(root: Path, command: Sequence[str]) -> str:
    try:
        result = subprocess.run(
            list(command), cwd=root, text=True, capture_output=True, check=True
        )
    except (OSError, subprocess.CalledProcessError) as error:
        raise MigrationError(f"could not determine migration provenance: {error}") from error
    return result.stdout.strip()


def report(results: Sequence[MigrationResult], *, before: bool = True) -> str:
    lifecycle_counts: dict[str, int] = {}
    approval_counts: dict[str, int] = {}
    ambiguous: list[MigrationResult] = []
    canonical = 0
    migrated = 0
    for result in results:
        lifecycle_counts[result.lifecycle] = lifecycle_counts.get(result.lifecycle, 0) + 1
        approval_counts[result.approval_state] = approval_counts.get(result.approval_state, 0) + 1
        canonical += int(result.canonical_before)
        migrated += int(result.changed)
        if result.ambiguous:
            ambiguous.append(result)

    lines = [
        "research_approval_migration=REPORT",
        f"total_eligible={len(results)}",
        f"canonical_before={canonical if before else 0}",
        f"proposed_changes={migrated}",
        "lifecycle_counts=" + ",".join(f"{key}:{lifecycle_counts[key]}" for key in sorted(lifecycle_counts)),
        "inferred_approval_counts=" + ",".join(f"{key}:{approval_counts[key]}" for key in sorted(approval_counts)),
        f"ambiguous_count={len(ambiguous)}",
    ]
    if ambiguous:
        lines.append("ambiguous_records:")
        lines.extend(
            f"- {result.relative_path}: {'; '.join(result.ambiguous)}"
            for result in ambiguous
        )
    canonical_records = [result.relative_path for result in results if result.canonical_before]
    if canonical_records:
        lines.append("already_canonical:")
        lines.extend(f"- {path}" for path in canonical_records)
    lines.append("proposed_mappings:")
    lines.extend(
        f"- {result.relative_path}: lifecycle={result.lifecycle} approval={result.approval_state}"
        for result in results
    )
    return "\n".join(lines)


def inspect_repository(
    root: Path,
    base_commit: str | None = None,
    *,
    normalize: bool = False,
) -> list[MigrationResult]:
    files = discover_research_files(root)
    commit = base_commit or _git_value(root, ("git", "rev-parse", "HEAD"))
    results: list[MigrationResult] = []
    for path in files:
        relative = path.relative_to(root)
        blob = _git_value(root, ("git", "hash-object", str(path)))
        try:
            result = migrate_document(
                path.read_text(encoding="utf-8"),
                relative_path=relative,
                base_commit=commit,
                base_blob=blob,
                normalize=normalize,
            )
        except MigrationError as error:
            raise MigrationError(f"{relative}: {error}") from error
        results.append(result)
    return results


def verify_against_base(root: Path, results: Sequence[MigrationResult]) -> tuple[int, int]:
    """Verify lifecycle and body preservation against recorded source commits."""

    lifecycle_checked = 0
    body_checked = 0
    for result in results:
        if not result.canonical_before:
            raise MigrationError(f"{result.relative_path}: canonical approval metadata is missing")
        current = _metadata_values(_split_header(result.text)[3])
        base_commit = current.get("approval_base_commit", "")
        if not base_commit:
            raise MigrationError(f"{result.relative_path}: missing approval base commit")
        try:
            source = subprocess.run(
                ["git", "show", f"{base_commit}:{result.relative_path.as_posix()}"],
                cwd=root,
                text=True,
                capture_output=True,
                check=True,
            ).stdout
        except (OSError, subprocess.CalledProcessError) as error:
            raise MigrationError(f"{result.relative_path}: cannot read approval base: {error}") from error
        _, _, source_body, source_metadata = _split_header(source)
        if source_body != result.body:
            raise MigrationError(f"{result.relative_path}: research body changed during migration")
        if source_metadata.get("status", [""])[0] != current.get("status", ""):
            raise MigrationError(f"{result.relative_path}: lifecycle keyword changed during migration")
        # Hash the recorded source through Git's blob algorithm instead of
        # relying on the current, metadata-augmented bytes.
        blob_result = subprocess.run(
            ["git", "hash-object", "--stdin"],
            cwd=root,
            input=source.encode("utf-8"),
            capture_output=True,
            check=True,
        )
        expected_blob = blob_result.stdout.decode("ascii").strip()
        if expected_blob != current.get("approval_base_blob", ""):
            raise MigrationError(f"{result.relative_path}: recorded approval base blob does not match source")
        lifecycle_checked += 1
        body_checked += 1
    return lifecycle_checked, body_checked


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Report and migrate legacy research approval metadata"
    )
    parser.add_argument("--root", type=Path, help="repository root")
    parser.add_argument("--base-commit", help="source commit to record in migrated metadata")
    parser.add_argument("--dry-run", action="store_true", help="report without writing files")
    parser.add_argument("--report", action="store_true", help="report proposed mappings without writing files")
    parser.add_argument("--check", action="store_true", help="fail if any document still needs migration")
    parser.add_argument("--verify", action="store_true", help="verify migrated bodies and lifecycle fields against recorded bases")
    parser.add_argument("--normalize", action="store_true", help="normalize already canonical header formatting before writing")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = (args.root or Path.cwd()).resolve()
    try:
        results = inspect_repository(root, args.base_commit, normalize=args.normalize)
    except (OSError, UnicodeError, MigrationError) as error:
        print(f"research_approval_migration=FAIL error={error}", file=sys.stderr)
        return 2

    print(report(results))
    if args.dry_run or args.report:
        return 0
    if args.check:
        pending_changes = [result.relative_path for result in results if result.changed]
        if pending_changes:
            print(
                f"research_approval_migration=FAIL unmigrated={len(pending_changes)}",
                file=sys.stderr,
            )
            return 1
        print("research_approval_migration=CHECK PASS unmigrated=0")
        if args.verify:
            try:
                lifecycle, body = verify_against_base(root, results)
            except MigrationError as error:
                print(f"research_approval_migration=FAIL verification={error}", file=sys.stderr)
                return 1
            print(f"verification=PASS lifecycle_preserved={lifecycle} body_preserved={body}")
        return 0
    for result in results:
        if result.changed:
            (root / result.relative_path).write_text(result.text, encoding="utf-8")
    print(f"migrated={sum(result.changed for result in results)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
