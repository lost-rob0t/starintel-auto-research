#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path
from typing import Sequence

SUBSTANTIVE_CLASSES = {
    "research",
    "design",
    "architecture",
    "implement",
    "implementation",
    "indexes",
    "specifications",
    "operations",
    "runbooks",
    "decisions",
    "projects",
    "actors",
    "providers",
}
ALLOWED_APPROVAL_STATES = {
    "PENDING",
    "NOT STARTED",
    "APPROVED",
    "REJECTED",
    "SUPERSEDED",
    "NOT APPLICABLE",
}
APPROVAL_HEADER = [
    "Approval area",
    "Required authority",
    "State",
    "Evidence required",
    "Evidence reference",
]
CHANGELOG_HEADER = ["Date", "Change", "Author or actor", "Evidence"]
REQUIRED_METADATA = ("title", "description", "status", "filetags")
ID_RE = re.compile(r"^\s*:ID:\s+(\S+)\s*$", re.MULTILINE | re.IGNORECASE)
KEYWORD_RE = re.compile(r"^#\+([A-Za-z0-9_-]+):\s*(.*?)\s*$", re.MULTILINE)
ID_LINK_RE = re.compile(r"\[\[id:([^\]\s]+)", re.IGNORECASE)
FILE_LINK_RE = re.compile(r"\[\[file:([^\]\n]+)", re.IGNORECASE)
PLANTUML_RE = re.compile(r"^#\+begin_src\s+plantuml\b", re.MULTILINE | re.IGNORECASE)
TABLE_ROW_RE = re.compile(r"^\s*\|(.*)\|\s*$")

APPROVAL_TEMPLATE = """* Approval Table

| Approval area | Required authority | State | Evidence required | Evidence reference |
|---------------+--------------------+-------+-------------------+--------------------|
| Research basis | Research reviewer | PENDING | Current primary-source verification | |
| Architecture | Project maintainer | PENDING | Design review and resolved contradictions | |
| Security | Security reviewer | PENDING | Authorization, disclosure, and secret-handling review | |
| Operations | Operator | PENDING | Operational policy, budgets, monitoring, and rollback review | |
| Implementation | Repository maintainer | NOT STARTED | Passing implementation, CI, and publication checks | |
"""


@dataclass(frozen=True)
class Problem:
    path: Path
    rule: str
    document_class: str
    correction: str

    def format(self, root: Path) -> str:
        try:
            shown = self.path.relative_to(root)
        except ValueError:
            shown = self.path
        return (
            f"{shown}: rule={self.rule}; class={self.document_class}; "
            f"correction={self.correction}"
        )


def project_root(start: Path | None = None) -> Path:
    current = (start or Path.cwd()).resolve()
    for candidate in (current, *current.parents):
        if (candidate / "AGENTS.md").is_file() and (candidate / "roam").is_dir():
            return candidate
    raise SystemExit("cannot locate repository root containing AGENTS.md and roam/")


def document_class(path: Path, root: Path) -> str | None:
    try:
        relative = path.relative_to(root / "roam")
    except ValueError:
        return None
    if not relative.parts:
        return None
    first = relative.parts[0].lower()
    return first if first in SUBSTANTIVE_CLASSES else None


def substantive_files(root: Path) -> list[Path]:
    roam = root / "roam"
    return sorted(
        path
        for path in roam.rglob("*.org")
        if path.is_file() and document_class(path, root) is not None
    )


def keyword_map(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for match in KEYWORD_RE.finditer(text):
        key = match.group(1).lower()
        result.setdefault(key, match.group(2).strip())
    return result


def section_bounds(text: str, title: str) -> tuple[int, int] | None:
    heading = re.compile(rf"^\*\s+{re.escape(title)}\s*$", re.MULTILINE | re.IGNORECASE)
    match = heading.search(text)
    if not match:
        return None
    next_heading = re.search(r"^\*\s+", text[match.end() :], re.MULTILINE)
    end = match.end() + (next_heading.start() if next_heading else len(text) - match.end())
    return match.start(), end


def parse_table(section: str) -> tuple[list[str], list[list[str]]]:
    rows: list[list[str]] = []
    for line in section.splitlines():
        match = TABLE_ROW_RE.match(line)
        if not match:
            continue
        cells = [cell.strip() for cell in match.group(1).split("|")]
        nonempty = [cell for cell in cells if cell]
        if nonempty and all(set(cell) <= {"-", "+", ":"} for cell in nonempty):
            continue
        rows.append(cells)
    if not rows:
        return [], []
    return rows[0], rows[1:]


def changed_files(root: Path, since: str | None) -> set[Path]:
    if not since:
        return set()
    result = subprocess.run(
        ["git", "diff", "--name-only", "--diff-filter=ACMRT", f"{since}...HEAD"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        raise SystemExit(result.stderr.strip() or f"git diff failed for {since}")
    return {(root / line).resolve() for line in result.stdout.splitlines() if line.strip()}


def stable_file_id(path: Path, root: Path) -> str:
    relative = path.relative_to(root / "roam").as_posix()
    return f"starintel-{hashlib.sha256(relative.encode('utf-8')).hexdigest()[:32]}"


def split_front_matter(text: str) -> tuple[str, str]:
    lines = text.splitlines(keepends=True)
    index = 0
    if lines and lines[0].strip().upper() == ":PROPERTIES:":
        index = 1
        while index < len(lines):
            if lines[index].strip().upper() == ":END:":
                index += 1
                break
            index += 1
    while index < len(lines) and (lines[index].startswith("#+") or not lines[index].strip()):
        index += 1
    return "".join(lines[:index]), "".join(lines[index:])


def ensure_metadata(text: str, path: Path, root: Path, cls: str) -> tuple[str, bool]:
    changed = False
    if not ID_RE.findall(text):
        text = f":PROPERTIES:\n:ID:       {stable_file_id(path, root)}\n:END:\n" + text
        changed = True

    keywords = keyword_map(text)
    title = keywords.get("title") or path.stem.replace("-", " ")
    additions: list[str] = []
    if "title" not in keywords:
        additions.append(f"#+title: {title}")
    if not keywords.get("description"):
        additions.append(f"#+description: {title}. Canonical StarIntel {cls} document.")
    if not keywords.get("status"):
        additions.append("#+status: DRAFT")
    if not keywords.get("filetags"):
        project = path.parent.name.lower().replace("_", "-")
        additions.append(f"#+filetags: :starintel:{cls}:{project}:")
    if additions:
        front, body = split_front_matter(text)
        text = front.rstrip() + "\n" + "\n".join(additions) + "\n\n" + body.lstrip("\n")
        changed = True
    return text, changed


def normalized_row(cells: Sequence[str], width: int) -> list[str]:
    values = list(cells[:width])
    values.extend([""] * (width - len(values)))
    return values


def ensure_approval(text: str) -> tuple[str, bool]:
    exemption = keyword_map(text).get("approval_exemption", "").strip()
    if exemption:
        return text, False
    bounds = section_bounds(text, "Approval Table")
    if bounds is None:
        front, body = split_front_matter(text)
        return front.rstrip() + "\n\n" + APPROVAL_TEMPLATE + "\n" + body.lstrip("\n"), True

    start, end = bounds
    section = text[start:end]
    header, rows = parse_table(section)
    if header == APPROVAL_HEADER:
        return text, False

    repaired_rows: list[list[str]] = []
    for row in rows:
        values = normalized_row(row, 5)
        if values[0].lower() == "approval area":
            continue
        state = values[2].upper()
        if state not in ALLOWED_APPROVAL_STATES:
            state = "PENDING"
        if state == "APPROVED" and not values[4].strip():
            state = "PENDING"
        values[2] = state
        repaired_rows.append(values)
    if not repaired_rows:
        replacement = APPROVAL_TEMPLATE.rstrip() + "\n"
    else:
        lines = [
            "* Approval Table",
            "",
            "| " + " | ".join(APPROVAL_HEADER) + " |",
            "|---------------+--------------------+-------+-------------------+--------------------|",
        ]
        lines.extend("| " + " | ".join(row) + " |" for row in repaired_rows)
        replacement = "\n".join(lines) + "\n"
    return text[:start] + replacement + text[end:].lstrip("\n"), True


def ensure_changelog(
    text: str,
    audit_date: str,
    actor: str,
    evidence: str,
    change_summary: str,
    force_entry: bool,
) -> tuple[str, bool]:
    exemption = keyword_map(text).get("changelog_exemption", "").strip()
    if exemption:
        return text, False
    bounds = section_bounds(text, "Changelog")
    changed = False
    if bounds is None:
        text = text.rstrip() + (
            "\n\n* Changelog\n\n"
            "| Date | Change | Author or actor | Evidence |\n"
            "|------+--------+-----------------+----------|\n"
            f"| {audit_date} | {change_summary} | {actor} | {evidence} |\n"
        )
        return text, True

    start, end = bounds
    section = text[start:end]
    header, rows = parse_table(section)
    if header != CHANGELOG_HEADER:
        normalized: list[list[str]] = []
        for row in rows:
            if row and row[0].lower() == "date":
                continue
            normalized.append(normalized_row(row, 4))
        lines = [
            "* Changelog",
            "",
            "| Date | Change | Author or actor | Evidence |",
            "|------+--------+-----------------+----------|",
        ]
        lines.extend("| " + " | ".join(row) + " |" for row in normalized)
        section = "\n".join(lines) + "\n"
        text = text[:start] + section + text[end:].lstrip("\n")
        changed = True
        bounds = section_bounds(text, "Changelog")
        assert bounds is not None
        start, end = bounds
        section = text[start:end]

    if force_entry and not re.search(
        rf"^\|\s*{re.escape(audit_date)}\s*\|", section, re.MULTILINE
    ):
        lines = section.rstrip().splitlines()
        lines.append(f"| {audit_date} | {change_summary} | {actor} | {evidence} |")
        replacement = "\n".join(lines) + "\n"
        text = text[:start] + replacement + text[end:].lstrip("\n")
        changed = True
    return text, changed


def ensure_glossary(text: str, captcha: bool) -> tuple[str, bool]:
    if section_bounds(text, "Footnotes and Glossary") is not None:
        return text, False
    if captcha:
        body = (
            "* Footnotes and Glossary\n\n"
            "- *CAPTCHA* — Completely Automated Public Turing test to tell Computers and Humans Apart.\n"
            "- *OCR* — Optical character recognition.\n"
            "- *Opaque reference* — A short-lived identifier that lets an authorized actor retrieve sensitive material without placing that material in documents or messages.\n"
        )
    else:
        body = (
            "* Footnotes and Glossary\n\n"
            "Document-specific acronyms and technical terms must be expanded on first use. Durable shared definitions should be linked by Org-roam ID rather than copied wholesale.\n"
        )
    return text.rstrip() + "\n\n" + body, True


def audit_document(
    path: Path,
    root: Path,
    all_ids: dict[str, list[Path]],
    changed: set[Path],
    audit_date: str,
) -> list[Problem]:
    cls = document_class(path, root) or "unknown"
    text = path.read_text(encoding="utf-8")
    problems: list[Problem] = []
    ids = ID_RE.findall(text)
    if not ids:
        problems.append(
            Problem(
                path,
                "missing-file-id",
                cls,
                "add a stable file-level :ID: property and preserve it thereafter",
            )
        )
    else:
        for identifier in ids:
            all_ids.setdefault(identifier, []).append(path)

    keywords = keyword_map(text)
    for key in REQUIRED_METADATA:
        if not keywords.get(key):
            problems.append(
                Problem(path, f"missing-{key}", cls, f"add a non-empty #+{key}: value")
            )

    approval_exemption = keywords.get("approval_exemption", "").strip()
    approval_bounds = section_bounds(text, "Approval Table")
    if not approval_bounds and not approval_exemption:
        problems.append(
            Problem(path, "missing-approval-table", cls, "add the canonical five-column Approval Table")
        )
    elif approval_exemption and len(approval_exemption) < 8:
        problems.append(
            Problem(path, "approval-exemption-without-reason", cls, "state a concrete exemption reason")
        )
    elif approval_bounds:
        header, rows = parse_table(text[approval_bounds[0] : approval_bounds[1]])
        if header != APPROVAL_HEADER:
            problems.append(
                Problem(path, "malformed-approval-header", cls, "use: " + " | ".join(APPROVAL_HEADER))
            )
        for row_number, raw in enumerate(rows, start=1):
            row = normalized_row(raw, 5)
            if row[0].lower() == "approval area":
                continue
            state = row[2].upper()
            if state not in ALLOWED_APPROVAL_STATES:
                problems.append(
                    Problem(
                        path,
                        f"invalid-approval-state-row-{row_number}",
                        cls,
                        f"use one of {sorted(ALLOWED_APPROVAL_STATES)}",
                    )
                )
            if state == "APPROVED" and not row[4].strip():
                problems.append(
                    Problem(
                        path,
                        f"approved-without-evidence-row-{row_number}",
                        cls,
                        "add a real evidence reference or downgrade the state",
                    )
                )
            if state == "NOT APPLICABLE" and not (row[3].strip() or row[4].strip()):
                problems.append(
                    Problem(
                        path,
                        f"not-applicable-without-reason-row-{row_number}",
                        cls,
                        "record why the approval area does not apply",
                    )
                )

    changelog_exemption = keywords.get("changelog_exemption", "").strip()
    changelog_bounds = section_bounds(text, "Changelog")
    if not changelog_bounds and not changelog_exemption:
        problems.append(
            Problem(path, "missing-changelog", cls, "add the canonical Changelog table")
        )
    elif changelog_exemption and len(changelog_exemption) < 8:
        problems.append(
            Problem(path, "changelog-exemption-without-reason", cls, "state a concrete exemption reason")
        )
    elif changelog_bounds:
        header, rows = parse_table(text[changelog_bounds[0] : changelog_bounds[1]])
        if header != CHANGELOG_HEADER:
            problems.append(
                Problem(path, "malformed-changelog-header", cls, "use: " + " | ".join(CHANGELOG_HEADER))
            )
        if not rows:
            problems.append(
                Problem(path, "empty-changelog", cls, "record at least the current verified material change")
            )
        if path.resolve() in changed and not any(
            row and row[0].strip() == audit_date for row in rows
        ):
            problems.append(
                Problem(
                    path,
                    "changed-without-current-changelog-entry",
                    cls,
                    f"add a {audit_date} changelog row describing this task's material change",
                )
            )

    if path.resolve() in changed and section_bounds(text, "Footnotes and Glossary") is None:
        problems.append(
            Problem(
                path,
                "changed-without-glossary",
                cls,
                "add a document-relevant Footnotes and Glossary section",
            )
        )

    if path.resolve() in changed:
        architectural = cls == "architecture" or ":architecture:" in keywords.get("filetags", "")
        captcha_design = cls == "design" and "captcha" in path.name.lower()
        if (architectural or captcha_design) and not PLANTUML_RE.search(text):
            problems.append(
                Problem(
                    path,
                    "architecture-without-plantuml",
                    cls,
                    "add a relevant, renderable PlantUML diagram",
                )
            )

    return problems


def audit_links(root: Path, files: Sequence[Path], ids: dict[str, list[Path]]) -> list[Problem]:
    known = set(ids)
    problems: list[Problem] = []
    for path in files:
        cls = document_class(path, root) or "unknown"
        text = path.read_text(encoding="utf-8")
        for identifier in ID_LINK_RE.findall(text):
            if identifier not in known:
                problems.append(
                    Problem(
                        path,
                        f"unresolved-id-link:{identifier}",
                        cls,
                        "link to an existing stable Org ID or repair the target ID",
                    )
                )
        for target_raw in FILE_LINK_RE.findall(text):
            target_part = target_raw.split("::", 1)[0]
            if not target_part or target_part.startswith(("http://", "https://", "/")):
                continue
            target = (path.parent / target_part).resolve()
            if not target.exists():
                problems.append(
                    Problem(
                        path,
                        f"unresolved-file-link:{target_raw}",
                        cls,
                        "repair the relative file link or replace it with a durable id: link",
                    )
                )
    return problems


def audit_repository_policy(root: Path) -> list[Problem]:
    problems: list[Problem] = []
    agents = (root / "AGENTS.md").read_text(encoding="utf-8")
    required_commands = (
        "python3 scripts/sync.py",
        "python3 scripts/sync.py --check",
        "bash scripts/publish-pages",
        "python3 scripts/check-pages-links.py _site",
    )
    for command in required_commands:
        if command not in agents:
            problems.append(
                Problem(
                    root / "AGENTS.md",
                    f"missing-canonical-command:{command}",
                    "agent-instructions",
                    "name the exact inspected repository command",
                )
            )
    required_phrases = (
        "auto-research.starintel.actor",
        "never hand-edit generated",
        "never claim a check passed",
        "nested AGENTS.md",
    )
    lower = agents.lower()
    for phrase in required_phrases:
        if phrase.lower() not in lower:
            problems.append(
                Problem(
                    root / "AGENTS.md",
                    f"missing-agent-rule:{phrase}",
                    "agent-instructions",
                    "add an operationally precise rule",
                )
            )

    workflow = root / ".github/workflows/pages.yml"
    if workflow.is_file():
        content = workflow.read_text(encoding="utf-8")
        for command in required_commands:
            if command not in content:
                problems.append(
                    Problem(
                        workflow,
                        f"ci-missing-canonical-command:{command}",
                        "ci-workflow",
                        "invoke the same canonical command used locally",
                    )
                )
    else:
        problems.append(
            Problem(
                workflow,
                "missing-pages-workflow",
                "ci-workflow",
                "restore the canonical complete-site validation and publication workflow",
            )
        )

    tracked = subprocess.run(
        ["git", "ls-files", "_site", ".cache"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if tracked.returncode == 0:
        for line in tracked.stdout.splitlines():
            problems.append(
                Problem(
                    root / line,
                    "tracked-generated-output",
                    "generated-output",
                    "remove generated site/cache output from version control",
                )
            )
    return problems


def audit_captcha_index(root: Path, files: Sequence[Path]) -> list[Problem]:
    captcha_files = [path for path in files if "captcha" in path.as_posix().lower()]
    index_candidates = [
        path
        for path in captcha_files
        if document_class(path, root) == "indexes" and "captcha" in path.name.lower()
    ]
    if not captcha_files:
        return []
    if not index_candidates:
        return [
            Problem(
                root / "roam/indexes",
                "missing-captcha-index",
                "indexes",
                "create one canonical CAPTCHA index linked by durable IDs",
            )
        ]
    index = sorted(index_candidates)[0]
    text = index.read_text(encoding="utf-8")
    problems: list[Problem] = []
    for path in captcha_files:
        if path == index:
            continue
        file_ids = ID_RE.findall(path.read_text(encoding="utf-8"))
        if not file_ids:
            continue
        identifier = file_ids[0]
        if f"id:{identifier}" not in text:
            problems.append(
                Problem(
                    index,
                    f"captcha-index-missing:{path.relative_to(root)}",
                    "indexes",
                    f"link the canonical document with [[id:{identifier}][...]]",
                )
            )
    return problems


def ensure_captcha_index(root: Path, files: Sequence[Path], audit_date: str, actor: str) -> int:
    captcha_files = [path for path in files if "captcha" in path.as_posix().lower()]
    index_candidates = [
        path
        for path in captcha_files
        if document_class(path, root) == "indexes" and "captcha" in path.name.lower()
    ]
    if not captcha_files or not index_candidates:
        return 0
    index = sorted(index_candidates)[0]
    original = index.read_text(encoding="utf-8")
    text = original
    missing: list[tuple[str, str]] = []
    for path in captcha_files:
        if path == index:
            continue
        source = path.read_text(encoding="utf-8")
        ids = ID_RE.findall(source)
        if not ids:
            continue
        identifier = ids[0]
        if f"id:{identifier}" not in text:
            title = keyword_map(source).get("title") or path.stem
            missing.append((identifier, title))
    if not missing:
        return 0
    rows = "".join(
        f"- [[id:{identifier}][{title}]]\n" for identifier, title in missing
    )
    bounds = section_bounds(text, "Canonical CAPTCHA Documents")
    if bounds is None:
        text = text.rstrip() + "\n\n* Canonical CAPTCHA Documents\n\n" + rows
    else:
        start, end = bounds
        section = text[start:end].rstrip() + "\n" + rows
        text = text[:start] + section + text[end:].lstrip("\n")
    text, _ = ensure_changelog(
        text,
        audit_date,
        actor,
        "repository audit and canonical ID inventory",
        "Updated CAPTCHA index coverage",
        True,
    )
    index.write_text(text.rstrip() + "\n", encoding="utf-8")
    return 1


def run_audit(root: Path, since: str | None, audit_date: str) -> list[Problem]:
    files = substantive_files(root)
    changed = changed_files(root, since)
    all_ids: dict[str, list[Path]] = {}
    problems: list[Problem] = []
    for path in files:
        problems.extend(audit_document(path, root, all_ids, changed, audit_date))
    for identifier, paths in sorted(all_ids.items()):
        unique = sorted(set(paths))
        if len(unique) > 1:
            for path in unique:
                cls = document_class(path, root) or "unknown"
                others = ", ".join(
                    str(other.relative_to(root)) for other in unique if other != path
                )
                problems.append(
                    Problem(
                        path,
                        f"duplicate-id:{identifier}",
                        cls,
                        f"preserve one canonical ID and repair duplicates; also used by {others}",
                    )
                )
    problems.extend(audit_links(root, files, all_ids))
    problems.extend(audit_repository_policy(root))
    problems.extend(audit_captcha_index(root, files))
    return sorted(problems, key=lambda item: (str(item.path), item.rule))


def fix_repository(root: Path, since: str | None, audit_date: str, actor: str) -> int:
    selected = substantive_files(root)
    changed_before = changed_files(root, since)
    modified = 0
    for path in selected:
        cls = document_class(path, root)
        assert cls is not None
        original = path.read_text(encoding="utf-8")
        text, structural = ensure_metadata(original, path, root, cls)
        text, approval_changed = ensure_approval(text)
        structural = structural or approval_changed
        captcha = "captcha" in path.as_posix().lower()
        force_glossary = structural or path.resolve() in changed_before
        if force_glossary:
            text, glossary_changed = ensure_glossary(text, captcha)
            structural = structural or glossary_changed
        force_entry = structural or path.resolve() in changed_before
        summary = (
            "Completed repository-wide structural audit repairs"
            if structural
            else "Updated material content during repository audit"
        )
        text, _ = ensure_changelog(
            text,
            audit_date,
            actor,
            "repository audit and tracked source diff",
            summary,
            force_entry,
        )
        if text != original:
            path.write_text(text.rstrip() + "\n", encoding="utf-8")
            modified += 1
    modified += ensure_captcha_index(root, selected, audit_date, actor)
    print(f"repaired {modified} substantive Org document(s)")
    return modified


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description=(
            "Audit StarIntel Org metadata, approvals, changelogs, links, indexes, "
            "and publication policy"
        )
    )
    parser.add_argument("--root", type=Path)
    parser.add_argument(
        "--changed-since",
        help=(
            "Git revision used to require a current changelog/glossary on "
            "materially changed files"
        ),
    )
    parser.add_argument(
        "--audit-date",
        default=os.environ.get("STARINTEL_AUDIT_DATE", date.today().isoformat()),
    )
    parser.add_argument(
        "--fix",
        action="store_true",
        help="repair deterministic structural omissions without fabricating approval",
    )
    parser.add_argument("--actor", default="repository audit agent")
    args = parser.parse_args(argv)

    root = project_root(args.root)
    if args.fix:
        fix_repository(root, args.changed_since, args.audit_date, args.actor)
    problems = run_audit(root, args.changed_since, args.audit_date)
    if problems:
        print(
            f"repository document audit found {len(problems)} violation(s):",
            file=sys.stderr,
        )
        for problem in problems:
            print(f"- {problem.format(root)}", file=sys.stderr)
        return 1
    print(
        "repository document audit passed for "
        f"{len(substantive_files(root))} substantive Org document(s)"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
