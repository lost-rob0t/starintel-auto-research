#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re, shutil, sys
from pathlib import Path
from _roamlib import (
    active_org_files,
    active_org_files_by_project,
    ensure_roam,
    implementation_slot_problems,
    mirror_structure,
    project_root,
    validate_org_headers,
)

def normalize_project(project: str) -> str:
    parts = Path(project).parts
    if len(parts) != 1 or parts[0] in {"", ".", ".."} or parts[0].startswith("."):
        raise SystemExit("project must be one visible immediate directory name")
    return parts[0]

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("design_file", nargs="?")
    parser.add_argument("--status", action="store_true")
    parser.add_argument("--clear", action="store_true")
    parser.add_argument("--project")
    parser.add_argument("--allow-closed", action="store_true")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    root, roam = project_root(), ensure_roam()
    problems = implementation_slot_problems(roam)
    if problems:
        raise SystemExit("\n".join(problems))
    active = active_org_files(roam)
    by_project = active_org_files_by_project(roam)
    if args.status:
        projects = {
            project: [str(path.relative_to(root)) for path in paths]
            for project, paths in sorted(by_project.items())
        }
        if args.project:
            project = normalize_project(args.project)
            projects = {project: projects.get(project, [])}
        payload = {
            "project_root": str(root),
            "active": [str(path.relative_to(root)) for path in active],
            "projects": projects,
            "valid": True,
        }
        print(json.dumps(payload, indent=2) if args.json else payload)
        return 0
    if args.clear:
        if args.project:
            project = normalize_project(args.project)
            selected = by_project.get(project, [])
        elif len(by_project) > 1:
            raise SystemExit("multiple project implementation slots are active; pass --project <project>")
        else:
            selected = active
        for path in selected:
            path.unlink()
        mirror_structure(roam)
        if args.project:
            print(f"implementation slot cleared for project {project}")
        else:
            print("implementation slot cleared")
        return 0
    if not args.design_file:
        parser.error("provide a design file, --status, or --clear")
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
    project = rel.parts[0] if len(rel.parts) > 1 else "."
    project_active = by_project.get(project, [])
    if project_active:
        raise SystemExit(
            f"implementation slot for project {project} occupied by "
            f"{project_active[0].relative_to(root)}"
        )
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
