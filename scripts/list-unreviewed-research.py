#!/usr/bin/env python3
"""List StarIntel research files that require an explicit human decision."""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

from research_queue import edit_url, load_items, repository_root, website_url


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=(
            "List canonical PENDING research plus legacy REVIEW/RESEARCHED/VERIFIED "
            "research that still needs a human decision."
        )
    )
    parser.add_argument(
        "--project",
        help="restrict results to one directory directly beneath roam/research",
    )
    parser.add_argument(
        "--show-legacy",
        action="store_true",
        help="include unmigrated lifecycle-only research (hidden by default)",
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

    visible = [item for item in items if args.show_legacy or not item.legacy]
    if not visible:
        scope = f" for project {args.project!r}" if args.project else ""
        suffix = " (legacy hidden)" if any(item.legacy for item in items) else ""
        print(f"No pending research found{scope}{suffix}.")
        return 0

    for index, item in enumerate(visible, start=1):
        print(f"{index}. {item.title}")
        print(f"   Lifecycle: {item.status}")
        print(f"   Approval: {item.approval_state}")
        print(f"   Project: {item.project}")
        print(f"   Website: {website_url(root, item.path)}")
        print(f"   Edit: {edit_url(root, item.path)}")

    hidden = sum(1 for item in items if item.legacy and not args.show_legacy)
    if hidden:
        print(f"\n{hidden} unmigrated review-ready item(s) hidden; pass --show-legacy to include them.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
