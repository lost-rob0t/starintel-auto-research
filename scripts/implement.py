#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import re
import sys
from pathlib import Path

from _roamlib import (
    active_org_files,
    active_org_files_by_project,
    ensure_roam,
    implementation_slot_problems,
    mirror_structure,
    project_root,
    upsert_header,
    validate_org_headers,
)

FILE_ID_RE = re.compile(
    r"\A(?P<prefix>\s*:PROPERTIES:\s*\n)(?P<body>.*?)(?P<suffix>^:END:\s*$)",
    re.MULTILINE | re.DOTALL | re.IGNORECASE,
)
ID_LINE_RE = re.compile(r"^:ID:\s+\S+\s*$", re.MULTILINE | re.IGNORECASE)
TITLE_RE = re.compile(r"(?im)^#\+title:\s*(.*?)\s*$")
DESCRIPTION_RE = re.compile(r"(?im)^#\+description:\s*(.*?)\s*$")
FILETAGS_RE = re.compile(r"(?im)^#\+filetags:\s*(.*?)\s*$")
CHANGELOG_HEADING_RE = re.compile(r"(?im)^\*\s+Changelog\s*$")
NEXT_TOP_HEADING_RE = re.compile(r"(?m)^\*\s+")


def normalize_project(project: str) -> str:
    parts = Path(project).parts
    if len(parts) != 1 or parts[0] in {"", ".", ".."} or parts[0].startswith("."):
        raise SystemExit("project must be one visible immediate directory name")
    return parts[0]


def file_id(text: str) -> str:
    drawer = FILE_ID_RE.search(text)
    if not drawer:
        raise SystemExit("design is missing a file-level property drawer")
    match = re.search(r"(?im)^:ID:\s+(\S+)\s*$", drawer.group("body"))
    if not match:
        raise SystemExit("design is missing a file-level :ID: property")
    return match.group(1)


def active_file_id(relative: Path) -> str:
    digest = hashlib.sha256(relative.as_posix().encode("utf-8")).hexdigest()[:24]
    return f"starintel-implementation-{digest}"


def replace_file_id(text: str, identifier: str) -> str:
    drawer = FILE_ID_RE.search(text)
    if not drawer:
        raise SystemExit("design is missing a file-level property drawer")
    body = drawer.group("body")
    if not ID_LINE_RE.search(body):
        raise SystemExit("design is missing a file-level :ID: property")
    body = ID_LINE_RE.sub(f":ID:       {identifier}", body, count=1)
    replacement = drawer.group("prefix") + body + drawer.group("suffix")
    return text[: drawer.start()] + replacement + text[drawer.end() :]


def ensure_implementation_tag(tags: str) -> str:
    normalized = tags.strip()
    if not normalized.startswith(":"):
        normalized = ":" + normalized
    if not normalized.endswith(":"):
        normalized += ":"
    if ":implementation:" not in normalized.lower():
        normalized += "implementation:"
    return normalized


def add_changelog_entry(text: str, canonical_id: str) -> str:
    today = dt.date.today().isoformat()
    row = (
        f"| {today} | Activated implementation working copy | "
        f"scripts/implement.py | Canonical design [[id:{canonical_id}][{canonical_id}]] |"
    )
    heading = CHANGELOG_HEADING_RE.search(text)
    if not heading:
        return text.rstrip() + (
            "\n\n* Changelog\n\n"
            "| Date | Change | Author or actor | Evidence |\n"
            "|------+--------+-----------------+----------|\n"
            f"{row}\n"
        )

    section_start = heading.end()
    next_heading = NEXT_TOP_HEADING_RE.search(text, section_start)
    section_end = next_heading.start() if next_heading else len(text)
    section = text[heading.start() : section_end]
    if re.search(rf"(?m)^\|\s*{re.escape(today)}\s*\|\s*Activated implementation working copy\s*\|", section):
        return text
    replacement = section.rstrip() + "\n" + row + "\n\n"
    return text[: heading.start()] + replacement + text[section_end:].lstrip("\n")


def implementation_copy(text: str, relative: Path) -> str:
    canonical_id = file_id(text)
    title_match = TITLE_RE.search(text)
    description_match = DESCRIPTION_RE.search(text)
    tags_match = FILETAGS_RE.search(text)
    title = title_match.group(1).strip() if title_match else relative.stem
    description = (
        description_match.group(1).strip()
        if description_match
        else f"Active implementation working copy of {title}."
    )
    tags = ensure_implementation_tag(tags_match.group(1) if tags_match else ":starintel:")

    text = replace_file_id(text, active_file_id(relative))
    text = upsert_header(text, "title", f"{title} — Active Implementation")
    text = upsert_header(
        text,
        "description",
        f"Active implementation working copy of the canonical design. {description}",
    )
    text = upsert_header(text, "status", "IMPLEMENTING")
    text = upsert_header(text, "filetags", tags)
    text = upsert_header(text, "canonical_id", canonical_id)

    if not re.search(r"(?im)^\*\s+Canonical Design\s*$", text):
        lines = text.splitlines(keepends=True)
        insert_at = 0
        if lines and lines[0].strip().upper() == ":PROPERTIES:":
            insert_at = 1
            while insert_at < len(lines):
                if lines[insert_at].strip().upper() == ":END:":
                    insert_at += 1
                    break
                insert_at += 1
        while insert_at < len(lines) and (
            lines[insert_at].startswith("#+") or not lines[insert_at].strip()
        ):
            insert_at += 1
        block = (
            "* Canonical Design\n\n"
            f"- [[id:{canonical_id}][{title}]]\n\n"
        )
        lines.insert(insert_at, block)
        text = "".join(lines)

    return add_changelog_entry(text, canonical_id).rstrip() + "\n"


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
            raise SystemExit(
                "multiple project implementation slots are active; pass --project <project>"
            )
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
        relative = source.relative_to(design_root)
    except ValueError as exc:
        raise SystemExit(f"design must be beneath {design_root}") from exc
    if not source.is_file():
        raise SystemExit(f"missing design file: {source}")
    validate_org_headers(source)
    project = relative.parts[0] if len(relative.parts) > 1 else "."
    project_active = by_project.get(project, [])
    if project_active:
        raise SystemExit(
            f"implementation slot for project {project} occupied by "
            f"{project_active[0].relative_to(root)}"
        )
    text = source.read_text(encoding="utf-8")
    if not args.allow_closed and re.search(
        r"(?im)^\#\+status:\s*(IMPLEMENTED|REJECTED)\s*$", text
    ):
        raise SystemExit("design is already closed; pass --allow-closed to reopen")

    destination = roam / "implement" / relative
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(implementation_copy(text, relative), encoding="utf-8")
    mirror_structure(roam)
    print(destination.relative_to(root))
    return 0


if __name__ == "__main__":
    sys.exit(main())
