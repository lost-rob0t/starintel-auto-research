#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re, shutil, sys
from pathlib import Path
from _roamlib import active_org_files, ensure_roam, mirror_structure, project_root, validate_org_headers

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("design_file", nargs="?")
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--clear", action="store_true")
    parser.add_argument("--allow-closed", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    root, roam = project_root(), ensure_roam()
    active = active_org_files(roam)
    if len(active) > 1:
        raise SystemExit("invalid implementation slot: more than one Org file")
    if args.status:
        payload = {"project_root": str(root), "active": [str(p.relative_to(root)) for p in active], "valid": True}
        print(json.dumps(payload, indent=2) if args.json else payload)
        return 0
    if args.clear:
        for path in active:
            path.unlink()
        mirror_structure(roam)
        print("implementation slot cleared")
        return 0
    if not args.design_file:
        parser.error("provide a design file, --status, or --clear")
    if active:
        raise SystemExit(f"implementation slot occupied by {active[0].relative_to(root)}")
    source = Path(args.design_file)
    source = (root / source).resolve() if not source.is_absolute() else source.resolve()
    design_root = (roam / "design").resolve()
    try:
        rel = source.relative_to(design_root)
    except ValueError as exc:
        raise SystemExit(f"design must be beneath {design_root}") from exc
    if not source.is_file():
        raise SystemExit(f"missing design file: {source}")
    validate_org_headers(source)
    text = source.read_text(encoding="utf-8")
    if not args.allow_closed and re.search(r"(?im)^\#\+status:\s*(IMPLEMENTED|REJECTED)\s*$", text):
        raise SystemExit("design is already closed; pass --allow-closed to reopen")
    destination = roam / "implement" / rel
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, destination)
    mirror_structure(roam)
    print(destination.relative_to(root))
    return 0

if __name__ == "__main__":
    sys.exit(main())
