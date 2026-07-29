#!/usr/bin/env python3
"""List Starintel research files that still require explicit review."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote

REPOSITORY = "lost-rob0t/starintel-auto-research"
BRANCH = "main"
SITE_BASE = "https://lost-rob0t.github.io/starintel-auto-research"
TERMINAL_STATUSES = frozenset({"DONE", "REJECTED"})
KEYWORD_RE = re.compile(r"^\s*#\+([A-Za-z0-9_-]+):\s*(.*?)\s*$", re.IGNORECASE)


@dataclass(frozen=True, slots=True)
class ResearchItem:
    path: Path
    title: str
    status: str
    project: str


def repository_root(script_path: Path) -> Path:
    candidate = script_path.resolve().parent.parent
    if (candidate / "roam" / "research").is_dir():
        return candidate

    current = Path.cwd().resolve()
    for directory in (current, *current.parents):
        if (directory / "roam" / "research").is_dir():
            return directory

    raise FileNotFoundError("cannot find roam/research from the script or current directory")


def parse_keywords(path: Path) -> dict[str, str]:
    keywords: dict[str, str] = {}
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            match = KEYWORD_RE.match(line)
            if match:
                keywords.setdefault(match.group(1).upper(), match.group(2).strip())
            if line.startswith("*"):
                break
    return keywords


def load_items(root: Path, project_filter: str | None) -> list[ResearchItem]:
    research_root = root / "roam" / "research"
    items: list[ResearchItem] = []

    for path in sorted(research_root.rglob("*.org")):
        relative = path.relative_to(research_root)
        project = relative.parts[0] if len(relative.parts) > 1 else "(root)"
        if project_filter and project != project_filter:
            continue

        keywords = parse_keywords(path)
        status = keywords.get("STATUS", "").strip().upper() or "MISSING"
        if status in TERMINAL_STATUSES:
            continue

        title = keywords.get("TITLE", "").strip() or path.stem
        items.append(ResearchItem(path=path, title=title, status=status, project=project))

    return items


def encoded_path(path: Path) -> str:
    return "/".join(quote(part, safe="") for part in path.parts)


def website_url(root: Path, path: Path) -> str:
    relative = path.relative_to(root / "roam").with_suffix(".html")
    return f"{SITE_BASE}/notes/{encoded_path(relative)}"


def edit_url(root: Path, path: Path) -> str:
    relative = path.relative_to(root)
    return f"https://github.com/{REPOSITORY}/edit/{BRANCH}/{encoded_path(relative)}"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="List Org research whose #+status is not DONE or REJECTED."
    )
    parser.add_argument(
        "--project",
        help="restrict results to one directory directly beneath roam/research",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)

    try:
        root = repository_root(Path(__file__))
        items = load_items(root, args.project)
    except (OSError, UnicodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1

    if not items:
        scope = f" for project {args.project!r}" if args.project else ""
        print(f"No unreviewed research found{scope}.")
        return 0

    for index, item in enumerate(items, start=1):
        print(f"{index}. {item.title}")
        print(f"   Status: {item.status}")
        print(f"   Project: {item.project}")
        print(f"   Website: {website_url(root, item.path)}")
        print(f"   Edit: {edit_url(root, item.path)}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
