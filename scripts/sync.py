#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, sys
from pathlib import Path
from _roamlib import TREE_NAMES, active_org_files, apply_event, ensure_roam, mirror_structure, project_root, read_jsonl, upsert_header

def write_jsonl(path: Path, values: list[dict]) -> None:
    with path.open("w", encoding="utf-8") as handle:
        for value in values:
            handle.write(json.dumps(value, sort_keys=True) + "\n")

def structure_diff(roam: Path) -> list[str]:
    by_tree, union = {}, set()
    for tree in TREE_NAMES:
        rels = {p.relative_to(roam / tree) for p in (roam / tree).rglob("*")
                if p.is_dir() and not any(part.startswith(".") for part in p.relative_to(roam / tree).parts)}
        by_tree[tree] = rels
        union.update(rels)
    return [f"missing directory: roam/{tree}/{rel}" for rel in sorted(union) for tree in TREE_NAMES if rel not in by_tree[tree]]

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--no-clear", action="store_true")
    args = parser.parse_args()
    root, roam = project_root(), ensure_roam()
    if args.check:
        problems = structure_diff(roam)
        active = active_org_files(roam)
        if len(active) > 1:
            problems.append(f"implementation slot contains {len(active)} Org files")
        for ledger in (".implemented", ".rejected"):
            for event in read_jsonl(roam / ledger):
                path = event.get("design_path")
                if not path or not (root / path).is_file():
                    problems.append(f"{ledger}: missing design {path}")
        if problems:
            print("\n".join(problems))
            return 2
        print("roam structure and ledgers are valid")
        return 0
    mirror_structure(roam)
    ledger_paths = [roam / ".implemented", roam / ".rejected"]
    ledgers = {p: read_jsonl(p) for p in ledger_paths}
    events = sorted([e for vals in ledgers.values() for e in vals], key=lambda e: e.get("timestamp", ""))
    synced, latest = set(), {}
    for event in events:
        eid, rel, status = event.get("event_id"), event.get("design_path"), event.get("status")
        if not eid or not rel or status not in {"IMPLEMENTED", "REJECTED"}:
            raise SystemExit(f"invalid status event: {event}")
        design = root / rel
        if not design.is_file():
            raise SystemExit(f"missing design: {rel}")
        text = apply_event(design.read_text(encoding="utf-8"), event)
        design.write_text(text, encoding="utf-8")
        latest[rel] = event
        synced.add(eid)
    for rel, event in latest.items():
        design = root / rel
        text = design.read_text(encoding="utf-8")
        text = upsert_header(text, "status", event["status"])
        text = upsert_header(text, "status_event", event["event_id"])
        text = upsert_header(text, "status_updated", event["timestamp"])
        design.write_text(text, encoding="utf-8")
    for path, vals in ledgers.items():
        for event in vals:
            if event.get("event_id") in synced:
                event["synced"] = True
        write_jsonl(path, vals)
    if not args.no_clear:
        active = active_org_files(roam)
        if len(active) > 1:
            raise SystemExit("cannot clear invalid implementation slot")
        if active:
            rel = str(active[0].relative_to(root))
            if any(e.get("active_path") == rel and e.get("event_id") in synced for e in events):
                active[0].unlink()
    mirror_structure(roam)
    print(f"synchronized {len(synced)} status event(s)")
    return 0

if __name__ == "__main__":
    sys.exit(main())
