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
from typing import Iterable, Sequence

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
    "todos",
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
SOURCE_BLOCK_RE = re.compile(
    r"^#\+begin_src\b.*?^#\+end_src\s*$",
    re.MULTILINE | re.IGNORECASE | re.DOTALL,
)
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

GLOSSARY_BY_CLASS = {
    "research": (
        "- *Primary source* — Original authoritative material used as direct evidence.\n"
        "- *Inference* — A conclusion derived from evidence and identified separately from a verified fact.\n"
    ),
    "design": (
        "- *Invariant* — A condition the design must preserve across every valid execution path.\n"
        "- *Actor* — An independently stateful component that processes messages through a defined protocol.\n"
    ),
    "architecture": (
        "- *Component boundary* — The explicit ownership and interface separating system responsibilities.\n"
        "- *Invariant* — A condition the architecture must preserve across valid deployments and failures.\n"
    ),
    "indexes": (
        "- *Canonical document* — The single maintained source node for one subject.\n"
        "- *Superseded* — Replaced by a named canonical document while retained for historical context.\n"
    ),
    "todos": (
        "- *Acceptance criterion* — An observable condition required before a task is complete.\n"
        "- *Dependency* — Work or evidence that must exist before this task can proceed.\n"
    ),
}
DEFAULT_GLOSSARY = (
    "- *Canonical document* — The single maintained source node for one subject.\n"
    "- *Evidence reference* — A durable pointer to the review, source, fixture, test, or command result supporting a claim.\n"
)
CAPTCHA_GLOSSARY = (
    "- *CAPTCHA* — Completely Automated Public Turing test to tell Computers and Humans Apart.\n"
    "- *OCR* — Optical character recognition.\n"
    "- *Opaque reference* — A short-lived identifier for authorized retrieval of sensitive material without placing that material in a document or message.\n"
)


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


def repository_root(start: Path | None = None) -> Path:
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
    value = relative.parts[0].lower()
    return value if value in SUBSTANTIVE_CLASSES else None


def substantive_files(root: Path) -> list[Path]:
    return sorted(
        path
        for path in (root / "roam").rglob("*.org")
        if path.is_file() and document_class(path, root) is not None
    )


def keyword_map(text: str) -> dict[str, str]:
    result: dict[str, str] = {}
    for match in KEYWORD_RE.finditer(text):
        result.setdefault(match.group(1).lower(), match.group(2).strip())
    return result


def section_bounds(text: str, title: str) -> tuple[int, int] | None:
    heading = re.compile(rf"^\*\s+{re.escape(title)}\s*$", re.MULTILINE | re.IGNORECASE)
    match = heading.search(text)
    if not match:
        return None
    following = re.search(r"^\*\s+", text[match.end() :], re.MULTILINE)
    end = match.end() + (following.start() if following else len(text) - match.end())
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
    return (rows[0], rows[1:]) if rows else ([], [])


def normalize_row(cells: Sequence[str], width: int) -> list[str]:
    result = list(cells[:width])
    result.extend([""] * (width - len(result)))
    return result


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
    digest = hashlib.sha256(relative.encode("utf-8")).hexdigest()[:32]
    return f"starintel-{digest}"


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

    metadata = keyword_map(text)
    title = metadata.get("title") or path.stem.replace("-", " ")
    additions: list[str] = []
    if not metadata.get("title"):
        additions.append(f"#+title: {title}")
    if not metadata.get("description"):
        additions.append(f"#+description: {title}. Canonical StarIntel {cls} document.")
    if not metadata.get("status"):
        additions.append("#+status: DRAFT")
    if not metadata.get("filetags"):
        project = path.parent.name.lower().replace("_", "-")
        additions.append(f"#+filetags: :starintel:{cls}:{project}:")
    if additions:
        front, body = split_front_matter(text)
        text = front.rstrip() + "\n" + "\n".join(additions) + "\n\n" + body.lstrip("\n")
        changed = True
    return text, changed


def normalized_approval_rows(rows: Iterable[Sequence[str]]) -> list[list[str]]:
    result: list[list[str]] = []
    for raw in rows:
        row = normalize_row(raw, 5)
        if row[0].lower() == "approval area":
            continue
        state = row[2].upper()
        if state not in ALLOWED_APPROVAL_STATES:
            state = "PENDING"
        if state == "APPROVED" and not row[4].strip():
            state = "PENDING"
        if state == "NOT APPLICABLE" and not (row[3].strip() or row[4].strip()):
            state = "PENDING"
        row[2] = state
        result.append(row)
    return result


def render_approval(rows: Sequence[Sequence[str]]) -> str:
    if not rows:
        return APPROVAL_TEMPLATE.rstrip() + "\n"
    lines = [
        "* Approval Table",
        "",
        "| " + " | ".join(APPROVAL_HEADER) + " |",
        "|---------------+--------------------+-------+-------------------+--------------------|",
    ]
    lines.extend("| " + " | ".join(row) + " |" for row in rows)
    return "\n".join(lines) + "\n"


def ensure_approval(text: str) -> tuple[str, bool]:
    if keyword_map(text).get("approval_exemption", "").strip():
        return text, False
    bounds = section_bounds(text, "Approval Table")
    if bounds is None:
        front, body = split_front_matter(text)
        return front.rstrip() + "\n\n" + APPROVAL_TEMPLATE + "\n" + body.lstrip("\n"), True

    start, end = bounds
    _, rows = parse_table(text[start:end])
    replacement = render_approval(normalized_approval_rows(rows))
    current = text[start:end].rstrip() + "\n"
    if replacement == current:
        return text, False
    return text[:start] + replacement + text[end:].lstrip("\n"), True


def render_changelog(rows: Sequence[Sequence[str]]) -> str:
    lines = [
        "* Changelog",
        "",
        "| Date | Change | Author or actor | Evidence |",
        "|------+--------+-----------------+----------|",
    ]
    lines.extend("| " + " | ".join(normalize_row(row, 4)) + " |" for row in rows)
    return "\n".join(lines) + "\n"


def ensure_changelog(
    text: str,
    audit_date: str,
    actor: str,
    change_summary: str,
    force_entry: bool,
) -> tuple[str, bool]:
    if keyword_map(text).get("changelog_exemption", "").strip():
        return text, False

    bounds = section_bounds(text, "Changelog")
    if bounds is None:
        row = [audit_date, change_summary, actor, "repository audit and tracked source diff"]
        return text.rstrip() + "\n\n" + render_changelog([row]), True

    start, end = bounds
    _, raw_rows = parse_table(text[start:end])
    rows = [normalize_row(row, 4) for row in raw_rows if not row or row[0].lower() != "date"]
    changed = False
    if force_entry and not any(row[0].strip() == audit_date for row in rows):
        rows.append([audit_date, change_summary, actor, "repository audit and tracked source diff"])
        changed = True
    replacement = render_changelog(rows)
    current = text[start:end].rstrip() + "\n"
    if replacement != current:
        changed = True
    if not changed:
        return text, False
    return text[:start] + replacement + text[end:].lstrip("\n"), True


def ensure_glossary(text: str, cls: str, captcha: bool) -> tuple[str, bool]:
    if section_bounds(text, "Footnotes and Glossary") is not None:
        return text, False
    body = CAPTCHA_GLOSSARY if captcha else GLOSSARY_BY_CLASS.get(cls, DEFAULT_GLOSSARY)
    return text.rstrip() + "\n\n* Footnotes and Glossary\n\n" + body, True


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

    identifiers = ID_RE.findall(text)
    if not identifiers:
        problems.append(Problem(path, "missing-file-id", cls, "add and preserve a stable file-level :ID:"))
    for identifier in identifiers:
        all_ids.setdefault(identifier, []).append(path)

    metadata = keyword_map(text)
    for key in REQUIRED_METADATA:
        if not metadata.get(key):
            problems.append(Problem(path, f"missing-{key}", cls, f"add a non-empty #+{key}: value"))

    approval_exemption = metadata.get("approval_exemption", "").strip()
    approval_bounds = section_bounds(text, "Approval Table")
    if not approval_bounds and not approval_exemption:
        problems.append(Problem(path, "missing-approval-table", cls, "add the canonical five-column Approval Table"))
    elif approval_exemption and len(approval_exemption) < 8:
        problems.append(Problem(path, "approval-exemption-without-reason", cls, "state a concrete exemption reason"))
    elif approval_bounds:
        header, rows = parse_table(text[approval_bounds[0] : approval_bounds[1]])
        if header != APPROVAL_HEADER:
            problems.append(Problem(path, "malformed-approval-header", cls, "use: " + " | ".join(APPROVAL_HEADER)))
        for number, raw in enumerate(rows, start=1):
            row = normalize_row(raw, 5)
            if row[0].lower() == "approval area":
                continue
            state = row[2].upper()
            if state not in ALLOWED_APPROVAL_STATES:
                problems.append(Problem(path, f"invalid-approval-state-row-{number}", cls, f"use one of {sorted(ALLOWED_APPROVAL_STATES)}"))
            if state == "APPROVED" and not row[4].strip():
                problems.append(Problem(path, f"approved-without-evidence-row-{number}", cls, "add real evidence or downgrade the state"))
            if state == "NOT APPLICABLE" and not (row[3].strip() or row[4].strip()):
                problems.append(Problem(path, f"not-applicable-without-reason-row-{number}", cls, "record why the approval area does not apply"))

    changelog_exemption = metadata.get("changelog_exemption", "").strip()
    changelog_bounds = section_bounds(text, "Changelog")
    if not changelog_bounds and not changelog_exemption:
        problems.append(Problem(path, "missing-changelog", cls, "add the canonical Changelog table"))
    elif changelog_exemption and len(changelog_exemption) < 8:
        problems.append(Problem(path, "changelog-exemption-without-reason", cls, "state a concrete exemption reason"))
    elif changelog_bounds:
        header, rows = parse_table(text[changelog_bounds[0] : changelog_bounds[1]])
        if header != CHANGELOG_HEADER:
            problems.append(Problem(path, "malformed-changelog-header", cls, "use: " + " | ".join(CHANGELOG_HEADER)))
        if not rows:
            problems.append(Problem(path, "empty-changelog", cls, "record at least the current verified material change"))
        if path.resolve() in changed and not any(row and row[0].strip() == audit_date for row in rows):
            problems.append(Problem(path, "changed-without-current-changelog-entry", cls, f"add a {audit_date} changelog row"))

    if path.resolve() in changed and section_bounds(text, "Footnotes and Glossary") is None:
        problems.append(Problem(path, "changed-without-glossary", cls, "add a document-relevant Footnotes and Glossary section"))

    architectural = cls == "architecture" or ":architecture:" in metadata.get("filetags", "")
    captcha_design = cls == "design" and "captcha" in path.as_posix().lower()
    if path.resolve() in changed and (architectural or captcha_design) and not PLANTUML_RE.search(text):
        problems.append(Problem(path, "architecture-without-plantuml", cls, "add a relevant renderable PlantUML diagram"))

    return problems


def link_visible_text(text: str) -> str:
    return SOURCE_BLOCK_RE.sub("", text)


def audit_links(root: Path, files: Sequence[Path], ids: dict[str, list[Path]]) -> list[Problem]:
    known_ids = set(ids)
    problems: list[Problem] = []
    for path in files:
        cls = document_class(path, root) or "unknown"
        text = link_visible_text(path.read_text(encoding="utf-8"))
        for identifier in ID_LINK_RE.findall(text):
            if identifier not in known_ids:
                problems.append(Problem(path, f"unresolved-id-link:{identifier}", cls, "link an existing stable ID or repair the target ID"))
        for raw_target in FILE_LINK_RE.findall(text):
            target_value = raw_target.split("::", 1)[0]
            if not target_value or target_value.startswith(("http://", "https://", "/")):
                continue
            target = (path.parent / target_value).resolve()
            if not target.exists():
                problems.append(Problem(path, f"unresolved-file-link:{raw_target}", cls, "repair the relative link or replace it with a durable id: link"))
    return problems


def audit_repository_policy(root: Path) -> list[Problem]:
    problems: list[Problem] = []
    agents_path = root / "AGENTS.md"
    agents = agents_path.read_text(encoding="utf-8")
    commands = (
        "python3 scripts/sync.py",
        "python3 scripts/sync.py --check",
        "python3 scripts/validate-docs.py",
        "bash scripts/publish-pages",
        "python3 scripts/check-pages-links.py _site",
    )
    for command in commands:
        if command not in agents:
            problems.append(Problem(agents_path, f"missing-canonical-command:{command}", "agent-instructions", "name the exact inspected repository command"))

    lower = agents.lower()
    for phrase in (
        "auto-research.starintel.actor",
        "never hand-edit generated output",
        "never claim a check passed",
        "nested `agents.md`",
    ):
        if phrase.lower() not in lower:
            problems.append(Problem(agents_path, f"missing-agent-rule:{phrase}", "agent-instructions", "add an operationally precise rule"))

    workflow = root / ".github/workflows/pages.yml"
    if not workflow.is_file():
        problems.append(Problem(workflow, "missing-pages-workflow", "ci-workflow", "restore canonical complete-site validation and publication"))
    else:
        content = workflow.read_text(encoding="utf-8")
        for command in commands:
            if command not in content:
                problems.append(Problem(workflow, f"ci-missing-canonical-command:{command}", "ci-workflow", "invoke the same canonical command used locally"))

    tracked = subprocess.run(
        ["git", "ls-files", "_site/**", ".cache/**"],
        cwd=root,
        text=True,
        capture_output=True,
        check=False,
    )
    if tracked.returncode == 0:
        for line in tracked.stdout.splitlines():
            problems.append(Problem(root / line, "tracked-generated-output", "generated-output", "remove generated site/cache output from version control"))
    return problems


def captcha_files(files: Sequence[Path]) -> list[Path]:
    return [path for path in files if "captcha" in path.as_posix().lower()]


def captcha_index(files: Sequence[Path], root: Path) -> Path | None:
    candidates = [
        path
        for path in captcha_files(files)
        if document_class(path, root) == "indexes" and "captcha" in path.name.lower()
    ]
    return sorted(candidates)[0] if candidates else None


def audit_captcha_index(root: Path, files: Sequence[Path]) -> list[Problem]:
    relevant = captcha_files(files)
    if not relevant:
        return []
    index = captcha_index(files, root)
    if index is None:
        return [Problem(root / "roam/indexes", "missing-captcha-index", "indexes", "create one canonical CAPTCHA index linked by durable IDs")]
    text = index.read_text(encoding="utf-8")
    problems: list[Problem] = []
    for path in relevant:
        if path == index:
            continue
        identifiers = ID_RE.findall(path.read_text(encoding="utf-8"))
        if identifiers and f"id:{identifiers[0]}" not in text:
            problems.append(Problem(index, f"captcha-index-missing:{path.relative_to(root)}", "indexes", f"link [[id:{identifiers[0]}][the canonical document]]"))
    return problems


def audit(root: Path, since: str | None, audit_date: str) -> list[Problem]:
    files = substantive_files(root)
    changed = changed_files(root, since)
    ids: dict[str, list[Path]] = {}
    problems: list[Problem] = []
    for path in files:
        problems.extend(audit_document(path, root, ids, changed, audit_date))
    for identifier, paths in sorted(ids.items()):
        unique = sorted(set(paths))
        if len(unique) > 1:
            for path in unique:
                other_paths = ", ".join(str(item.relative_to(root)) for item in unique if item != path)
                problems.append(Problem(path, f"duplicate-id:{identifier}", document_class(path, root) or "unknown", f"preserve one canonical ID and repair duplicates; also used by {other_paths}"))
    problems.extend(audit_links(root, files, ids))
    problems.extend(audit_repository_policy(root))
    problems.extend(audit_captcha_index(root, files))
    return sorted(problems, key=lambda item: (str(item.path), item.rule))


def ensure_captcha_index(root: Path, files: Sequence[Path], audit_date: str, actor: str) -> int:
    index = captcha_index(files, root)
    if index is None:
        return 0
    original = index.read_text(encoding="utf-8")
    text = original
    additions: list[tuple[str, str]] = []
    for path in captcha_files(files):
        if path == index:
            continue
        source = path.read_text(encoding="utf-8")
        identifiers = ID_RE.findall(source)
        if not identifiers or f"id:{identifiers[0]}" in text:
            continue
        title = keyword_map(source).get("title") or path.stem
        additions.append((identifiers[0], title))
    if not additions:
        return 0
    rows = "".join(f"- [[id:{identifier}][{title}]]\n" for identifier, title in additions)
    bounds = section_bounds(text, "Canonical CAPTCHA Documents")
    if bounds is None:
        text = text.rstrip() + "\n\n* Canonical CAPTCHA Documents\n\n" + rows
    else:
        start, end = bounds
        replacement = text[start:end].rstrip() + "\n" + rows
        text = text[:start] + replacement + text[end:].lstrip("\n")
    text, _ = ensure_changelog(text, audit_date, actor, "Updated canonical CAPTCHA index coverage", True)
    index.write_text(text.rstrip() + "\n", encoding="utf-8")
    return 1


def fix(root: Path, since: str | None, audit_date: str, actor: str) -> int:
    changed_before = changed_files(root, since)
    modified = 0
    for path in substantive_files(root):
        cls = document_class(path, root)
        assert cls is not None
        original = path.read_text(encoding="utf-8")
        text, metadata_changed = ensure_metadata(original, path, root, cls)
        text, approval_changed = ensure_approval(text)
        structural = metadata_changed or approval_changed
        needs_current_entry = structural or path.resolve() in changed_before
        if needs_current_entry:
            text, glossary_changed = ensure_glossary(text, cls, "captcha" in path.as_posix().lower())
            structural = structural or glossary_changed
        summary = "Completed repository-wide structural audit repairs" if structural else "Updated material content during repository audit"
        text, changelog_changed = ensure_changelog(text, audit_date, actor, summary, needs_current_entry)
        if changelog_changed:
            structural = True
        if text != original:
            path.write_text(text.rstrip() + "\n", encoding="utf-8")
            modified += 1
    modified += ensure_captcha_index(root, substantive_files(root), audit_date, actor)
    print(f"repaired {modified} substantive Org document(s)")
    return modified


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Audit StarIntel Org metadata, approvals, changelogs, links, indexes, and publication policy")
    parser.add_argument("--root", type=Path)
    parser.add_argument("--changed-since", help="Git revision used to require current history and glossary for materially changed files")
    parser.add_argument("--audit-date", default=os.environ.get("STARINTEL_AUDIT_DATE", date.today().isoformat()))
    parser.add_argument("--fix", action="store_true", help="repair deterministic structural omissions without fabricating approval")
    parser.add_argument("--actor", default="repository audit agent")
    args = parser.parse_args(argv)

    root = repository_root(args.root)
    if args.fix:
        fix(root, args.changed_since, args.audit_date, args.actor)
    problems = audit(root, args.changed_since, args.audit_date)
    if problems:
        print(f"repository document audit found {len(problems)} violation(s):", file=sys.stderr)
        for problem in problems:
            print(f"- {problem.format(root)}", file=sys.stderr)
        return 1
    print(f"repository document audit passed for {len(substantive_files(root))} substantive Org document(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
