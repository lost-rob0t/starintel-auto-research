#!/usr/bin/env python3
from __future__ import annotations
import argparse, sys
from pathlib import Path
from _roamlib import (
    active_org_files,
    active_org_files_by_project,
    append_jsonl,
    canonical_from_active,
    ensure_roam,
    implementation_slot_problems,
    new_event_id,
    now_iso,
    project_root,
    read_jsonl,
)

def normalize_project(project: str) -> str:
    parts = Path(project).parts
    if len(parts) != 1 or parts[0] in {"", ".", ".."} or parts[0].startswith("."):
        raise SystemExit("project must be one visible immediate directory name")
    return parts[0]

def main() -> int:
    parser = argparse.ArgumentParser()
    subs = parser.add_subparsers(dest="status", required=True)
    imp = subs.add_parser("implemented")
    imp.add_argument("--project")
    imp.add_argument("--summary", required=True)
    imp.add_argument("--file", action="append", default=[])
    imp.add_argument("--test", action="append", default=[])
    imp.add_argument("--commit", action="append", default=[])
    imp.add_argument("--note", action="append", default=[])
    rej = subs.add_parser("rejected")
    rej.add_argument("--project")
    rej.add_argument("--reason", required=True)
    rej.add_argument("--evidence", action="append", default=[])
    rej.add_argument("--replacement", default="")
    rej.add_argument("--note", action="append", default=[])
    parser.add_argument("--force", action="store_true")
    args = parser.parse_args()
    root, roam = project_root(), ensure_roam()
    problems = implementation_slot_problems(roam)
    if problems:
        raise SystemExit("\n".join(problems))
    all_active = active_org_files(roam)
    by_project = active_org_files_by_project(roam)
    if args.project:
        project = normalize_project(args.project)
        active = by_project.get(project, [])
        if len(active) != 1:
            raise SystemExit(f"expected one active design for project {project}; found {len(active)}")
    else:
        if len(all_active) != 1:
            raise SystemExit(
                f"expected exactly one active design or --project <project>; found {len(all_active)}"
            )
        active = all_active
    active_path = active[0]
    canonical = canonical_from_active(active_path, roam)
    if not canonical.is_file():
        raise SystemExit(f"canonical design missing: {canonical.relative_to(root)}")
    prior = read_jsonl(roam / ".implemented") + read_jsonl(roam / ".rejected")
    canonical_rel = str(canonical.relative_to(root))
    if not args.force and any(e.get("design_path") == canonical_rel and not e.get("synced", False) for e in prior):
        raise SystemExit("unsynchronized status event exists; run scripts/sync.py")
    status = args.status.upper()
    event = {"event_id": new_event_id(), "status": status, "timestamp": now_iso(),
             "design_path": canonical_rel, "active_path": str(active_path.relative_to(root)), "synced": False}
    if status == "IMPLEMENTED":
        event.update(summary=args.summary, files=args.file, tests=args.test, commits=args.commit, notes=args.note)
        ledger = roam / ".implemented"
    else:
        event.update(reason=args.reason, evidence=args.evidence, replacement=args.replacement, notes=args.note)
        ledger = roam / ".rejected"
    append_jsonl(ledger, event)
    print(f"{status}: {canonical_rel}\nevent: {event['event_id']}\nrun: python scripts/sync.py")
    return 0

if __name__ == "__main__":
    sys.exit(main())
