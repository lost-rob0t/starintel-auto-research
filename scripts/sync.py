#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from _roamlib import (
    TREE_NAMES,
    active_org_files,
    apply_event,
    ensure_roam,
    implementation_slot_problems,
    mirror_structure,
    project_root,
    read_jsonl,
    upsert_header,
)


def write_jsonl(path: Path, values: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for value in values:
            handle.write(json.dumps(value, sort_keys=True) + "\n")


def structure_diff(roam: Path) -> list[str]:
    by_tree: dict[str, set[Path]] = {}
    union: set[Path] = set()
    for tree in TREE_NAMES:
        rels = {
            path.relative_to(roam / tree)
            for path in (roam / tree).rglob("*")
            if path.is_dir()
            and not any(
                part.startswith(".")
                for part in path.relative_to(roam / tree).parts
            )
        }
        by_tree[tree] = rels
        union.update(rels)
    return [
        f"missing directory: roam/{tree}/{relative}"
        for relative in sorted(union)
        for tree in TREE_NAMES
        if relative not in by_tree[tree]
    ]


def validate_documents(root: Path) -> int:
    validator = root / "scripts" / "validate-docs.py"
    if not validator.is_file():
        print(f"missing repository document validator: {validator}", file=sys.stderr)
        return 2
    result = subprocess.run(
        [sys.executable, str(validator), "--root", str(root)],
        cwd=root,
        check=False,
    )
    return result.returncode


def check_repository(root: Path, roam: Path) -> int:
    problems = structure_diff(roam)
    problems.extend(implementation_slot_problems(roam))
    for ledger in (".implemented", ".rejected"):
        for event in read_jsonl(roam / ledger):
            path = event.get("design_path")
            if not path or not (root / path).is_file():
                problems.append(f"{ledger}: missing design {path}")
    if problems:
        print("\n".join(problems), file=sys.stderr)
        return 2

    print("roam structure and ledgers are valid")
    return validate_documents(root)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--no-clear", action="store_true")
    args = parser.parse_args()
    root, roam = project_root(), ensure_roam()

    if args.check:
        return check_repository(root, roam)

    mirror_structure(roam)
    slot_problems = implementation_slot_problems(roam)
    if slot_problems:
        raise SystemExit("\n".join(slot_problems))

    ledger_paths = [roam / ".implemented", roam / ".rejected"]
    ledgers = {path: read_jsonl(path) for path in ledger_paths}
    events = sorted(
        [event for values in ledgers.values() for event in values],
        key=lambda event: event.get("timestamp", ""),
    )
    synced: set[str] = set()
    latest: dict[str, dict] = {}

    for event in events:
        event_id = event.get("event_id")
        relative = event.get("design_path")
        status = event.get("status")
        if not event_id or not relative or status not in {"IMPLEMENTED", "REJECTED"}:
            raise SystemExit(f"invalid status event: {event}")
        design = root / relative
        if not design.is_file():
            raise SystemExit(f"missing design: {relative}")
        text = apply_event(design.read_text(encoding="utf-8"), event)
        design.write_text(text, encoding="utf-8")
        latest[relative] = event
        synced.add(event_id)

    for relative, event in latest.items():
        design = root / relative
        text = design.read_text(encoding="utf-8")
        text = upsert_header(text, "status", event["status"])
        text = upsert_header(text, "status_event", event["event_id"])
        text = upsert_header(text, "status_updated", event["timestamp"])
        design.write_text(text, encoding="utf-8")

    for path, values in ledgers.items():
        for event in values:
            if event.get("event_id") in synced:
                event["synced"] = True
        write_jsonl(path, values)

    if not args.no_clear:
        for active_path in active_org_files(roam):
            relative = str(active_path.relative_to(root))
            if any(
                event.get("active_path") == relative
                and event.get("event_id") in synced
                for event in events
            ):
                active_path.unlink()

    mirror_structure(roam)
    print(f"synchronized {len(synced)} status event(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
