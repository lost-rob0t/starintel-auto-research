#!/usr/bin/env python3
"""Shared research-review queue semantics for CLI and Pages views."""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from urllib.parse import quote

REPOSITORY = "lost-rob0t/starintel-auto-research"
BRANCH = "main"
SITE_BASE = "https://auto-research.starintel.actor"
CANONICAL_PENDING = "PENDING"
LEGACY_REVIEW_READY = frozenset({"REVIEW", "RESEARCHED", "VERIFIED"})
AUXILIARY_FILENAMES = frozenset({"index.org", "sources.org", "search-log.org"})
KEYWORD_RE = re.compile(r"^\s*#\+([A-Za-z0-9_-]+):\s*(.*?)\s*$", re.IGNORECASE)


@dataclass(frozen=True, slots=True)
class ResearchItem:
    path: Path
    relative_path: Path
    title: str
    status: str
    project: str
    approval_state: str
    approval_schema: str
    last_modified: str
    legacy: bool


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


def _project_for(relative: Path) -> str:
    return relative.parts[0] if len(relative.parts) > 1 else "(root)"


def _review_class(keywords: dict[str, str]) -> tuple[bool, bool, str, str]:
    """Return (reviewable, legacy, lifecycle, approval_state)."""
    lifecycle = keywords.get("STATUS", "").strip().upper() or "MISSING"
    approval_state = keywords.get("APPROVAL_STATE", "").strip().upper()
    approval_schema = keywords.get("APPROVAL_SCHEMA", "").strip()

    if approval_state:
        return approval_state == CANONICAL_PENDING, False, lifecycle, approval_state

    # A document that started canonical migration should not silently fall back
    # to legacy lifecycle semantics when its approval metadata is incomplete.
    if approval_schema:
        return False, False, lifecycle, "INVALID"

    return lifecycle in LEGACY_REVIEW_READY, True, lifecycle, "UNMIGRATED"


def load_items(root: Path, project_filter: str | None = None) -> list[ResearchItem]:
    research_root = root / "roam" / "research"
    items: list[ResearchItem] = []

    for path in sorted(research_root.rglob("*.org")):
        if path.name.lower() in AUXILIARY_FILENAMES:
            continue

        relative = path.relative_to(research_root)
        project = _project_for(relative)
        if project_filter and project != project_filter:
            continue

        keywords = parse_keywords(path)
        reviewable, legacy, status, approval_state = _review_class(keywords)
        if not reviewable:
            continue

        title = keywords.get("TITLE", "").strip() or path.stem
        items.append(
            ResearchItem(
                path=path,
                relative_path=relative,
                title=title,
                status=status,
                project=project,
                approval_state=approval_state,
                approval_schema=keywords.get("APPROVAL_SCHEMA", "").strip(),
                last_modified=(
                    keywords.get("LAST_MODIFIED", "").strip()
                    or keywords.get("LAST-MODIFIED", "").strip()
                    or keywords.get("CREATED", "").strip()
                ),
                legacy=legacy,
            )
        )

    return items


def encoded_path(path: Path) -> str:
    return "/".join(quote(part, safe="") for part in path.parts)


def website_url(root: Path, path: Path) -> str:
    relative = path.relative_to(root / "roam").with_suffix(".html")
    return f"{SITE_BASE}/notes/{encoded_path(relative)}"


def relative_website_url(root: Path, path: Path, *, prefix: str = "../") -> str:
    relative = path.relative_to(root / "roam").with_suffix(".html")
    return f"{prefix}notes/{encoded_path(relative)}"


def edit_url(root: Path, path: Path) -> str:
    relative = path.relative_to(root)
    return f"https://github.com/{REPOSITORY}/edit/{BRANCH}/{encoded_path(relative)}"


def source_url(root: Path, path: Path) -> str:
    relative = path.relative_to(root)
    return f"https://github.com/{REPOSITORY}/blob/{BRANCH}/{encoded_path(relative)}"
