#!/usr/bin/env python3
from __future__ import annotations
import argparse, datetime as dt, re, sys
from _roamlib import ensure_roam, mirror_structure, project_root

def slugify(v: str) -> str:
    s = re.sub(r"[^a-z0-9]+", "-", v.lower()).strip("-")
    if not s: raise SystemExit("invalid slug")
    return s

def main() -> int:
    p = argparse.ArgumentParser()
    p.add_argument("--project", required=True); p.add_argument("--title", required=True)
    p.add_argument("--description", default=""); p.add_argument("--finding", action="append", default=[])
    p.add_argument("--source", action="append", default=[]); p.add_argument("--repository", action="append", default=[])
    p.add_argument("--commit", action="append", default=[]); p.add_argument("--design-file", action="append", default=[])
    p.add_argument("--next-action", default=""); m = p.add_mutually_exclusive_group(required=True)
    m.add_argument("--draft", action="store_true"); m.add_argument("--final", action="store_true")
    p.add_argument("--append", action="store_true"); a = p.parse_args()
    root, roam = project_root(), ensure_roam()
    directory = roam / "research" / slugify(a.project); directory.mkdir(parents=True, exist_ok=True); mirror_structure(roam)
    path = directory / f"{slugify(a.title)}.org"
    if path.exists() and not a.append: raise SystemExit(f"refusing overwrite: {path.relative_to(root)}")
    if a.append and not path.exists(): raise SystemExit(f"cannot append missing note: {path.relative_to(root)}")
    now = dt.datetime.now().astimezone(); timestamp, date = now.isoformat(timespec="seconds"), now.strftime("%Y-%m-%d")
    state, tags = ("DRAFT", ":starintel:research:draft:") if a.draft else ("DONE", ":starintel:research:")
    if not path.exists():
        path.write_text(f"#+title: {a.title}\n#+description: {a.description}\n#+filetags: {tags}\n#+todo: DRAFT RESEARCH REVIEW | DONE REJECTED\n\n* {state} Objective\n\n{a.description or 'TODO'}\n\n* {state} Findings\n", encoding="utf-8")
    with path.open("a", encoding="utf-8") as h:
        h.write(f"\n** {state} Research update {timestamp}\n")
        for v in a.finding or ["TODO"]: h.write(f"- {v}\n")
        h.write("\n*** Sources\n")
        for v in a.source or ["TODO"]: h.write(f"- Retrieved {date}: {v}\n")
        h.write("\n*** Repositories Reviewed\n")
        for v in a.repository or ["None"]: h.write(f"- {v}\n")
        h.write("\n*** Commits Reviewed\n")
        for v in a.commit or ["None"]: h.write(f"- {v}\n")
        h.write("\n*** Affected Design Files\n")
        for v in a.design_file or ["TODO"]: h.write(f"- {v}\n")
        h.write(f"\n*** Next Action\n{a.next_action or 'TODO'}\n")
    print(path.relative_to(root)); return 0

if __name__ == "__main__":
    sys.exit(main())
