#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, re, sys
from dataclasses import asdict, dataclass
from _roamlib import ensure_roam, project_root

@dataclass
class Result:
    path: str
    title: str
    description: str
    tags: list[str]
    score: int
    matched_terms: list[str]

def header(text: str, key: str) -> str:
    match = re.search(rf"(?im)^\#\+{re.escape(key)}:\s*(.+?)\s*$", text)
    return match.group(1).strip() if match else ""

def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("query")
    parser.add_argument("--project")
    parser.add_argument("--status")
    parser.add_argument("--tag", action="append", default=[])
    parser.add_argument("--limit", type=int, default=12)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args()
    root, roam = project_root(), ensure_roam()
    terms = [t.lower() for t in re.findall(r"[\w.-]+", args.query)]
    if not terms:
        raise SystemExit("query has no searchable terms")
    results = []
    for path in roam.rglob("*.org"):
        text, rel = path.read_text(encoding="utf-8"), path.relative_to(root)
        if args.project and args.project.lower() not in str(rel).lower():
            continue
        if args.status and not re.search(rf"(?im)^\#\+status:\s*{re.escape(args.status)}\s*$", text):
            continue
        tags = [p for p in header(text, "filetags").split(":") if p]
        if args.tag and not all(tag in tags for tag in args.tag):
            continue
        title, desc, lower, score, matched = header(text, "title") or path.stem, header(text, "description"), text.lower(), 0, []
        for term in terms:
            count = lower.count(term)
            if count:
                matched.append(term); score += min(count, 10)
                if term in title.lower(): score += 12
                if term in desc.lower(): score += 6
        if score:
            results.append(Result(str(rel), title, desc, tags, score, matched))
    results.sort(key=lambda x: (-x.score, x.path))
    results = results[:max(args.limit, 1)]
    if args.json:
        print(json.dumps([asdict(x) for x in results], indent=2))
    else:
        for x in results:
            print(f"{x.score:>3}  {x.path}\n     {x.title}")
            if x.description: print(f"     {x.description}")
    return 0

if __name__ == "__main__":
    sys.exit(main())
