#!/usr/bin/env python3
from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
import uuid
from pathlib import Path

from _roamlib import ensure_roam, mirror_structure, project_root


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    if not slug:
        raise SystemExit("invalid slug")
    return slug


def replace_or_insert_metadata(text: str, key: str, value: str) -> str:
    pattern = re.compile(rf"^#\+{re.escape(key)}:.*$", re.MULTILINE)
    replacement = f"#+{key}: {value}"
    if pattern.search(text):
        return pattern.sub(replacement, text, count=1)

    lines = text.splitlines()
    insert_at = 0
    for index, line in enumerate(lines):
        if line.startswith("#+") or line in {":PROPERTIES:", ":END:"} or line.startswith(":ID:"):
            insert_at = index + 1
    lines.insert(insert_at, replacement)
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")


def append_changelog_row(text: str, row: str) -> str:
    heading = "* Changelog\n"
    if heading not in text:
        block = (
            "\n* Changelog\n\n"
            "| Date | Change | Author or actor | Evidence |\n"
            "|------+--------+-----------------+----------|\n"
            f"{row}\n"
        )
        marker = "\n* Footnotes and Glossary"
        if marker in text:
            return text.replace(marker, block + marker, 1)
        return text.rstrip() + block + "\n"

    start = text.index(heading) + len(heading)
    next_heading = text.find("\n* ", start)
    end = len(text) if next_heading == -1 else next_heading
    section = text[start:end]
    lines = section.splitlines()

    insert_at = None
    for index, line in enumerate(lines):
        if line.startswith("|-"):
            insert_at = index + 1
            break
    if insert_at is None:
        raise SystemExit("malformed Changelog table")

    lines.insert(insert_at, row)
    replacement = "\n".join(lines)
    return text[:start] + replacement + text[end:]


def insert_before_glossary(text: str, block: str) -> str:
    marker = "\n* Footnotes and Glossary"
    if marker in text:
        return text.replace(marker, block.rstrip() + "\n" + marker, 1)
    return text.rstrip() + "\n" + block.rstrip() + "\n"


def research_update(args: argparse.Namespace, state: str, timestamp: str, date: str) -> str:
    lines = [f"\n** {state} Research update {timestamp}"]
    for value in args.finding or ["TODO"]:
        lines.append(f"- {value}")

    lines.extend(["", "*** Sources"])
    for value in args.source or ["TODO"]:
        lines.append(f"- Retrieved {date}: {value}")

    lines.extend(["", "*** Repositories Reviewed"])
    for value in args.repository or ["None"]:
        lines.append(f"- {value}")

    lines.extend(["", "*** Commits Reviewed"])
    for value in args.commit or ["None"]:
        lines.append(f"- {value}")

    lines.extend(["", "*** Affected Design Files"])
    for value in args.design_file or ["TODO"]:
        lines.append(f"- {value}")

    lines.extend(["", "*** Next Action", args.next_action or "TODO", ""])
    return "\n".join(lines)


def new_research_document(
    args: argparse.Namespace,
    *,
    state: str,
    timestamp: str,
    date: str,
    project_slug: str,
) -> str:
    stable_id = f"starintel-research-{project_slug}-{slugify(args.title)}-{uuid.uuid4().hex[:12]}"
    description = args.description or "TODO"
    update = research_update(args, state, timestamp, date)

    return f""":PROPERTIES:
:ID:       {stable_id}
:END:
#+title: {args.title}
#+description: {description}
#+status: {state}
#+approval_schema: adard.research-approval.v1
#+approval_state: PENDING
#+approval_actor: research-worker
#+approval_evidence: worker-authored research requires explicit human research-conclusion approval
#+approval_base_commit: NONE
#+approval_base_blob: NONE
#+approval_decided_at: NONE
#+created: [{date}]
#+last_modified: [{date}]
#+filetags: :starintel:research:{project_slug}:
#+todo: TODO RESEARCHING REVIEW BLOCKED | DONE REJECTED

* Approval Table

| Approval area | Required authority | State | Evidence required | Evidence reference |
|---------------+--------------------+-------+-------------------+--------------------|
| Research conclusion | StarIntel operator | PENDING | Explicit human approval of the research conclusion | |
| Architecture/design | StarIntel operator | NOT STARTED | Approved research plus explicit human design approval | |
| Implementation | Repository maintainer | NOT STARTED | Explicitly approved governing design/contract plus implementation evidence | |

* Changelog

| Date | Change | Author or actor | Evidence |
|------+--------+-----------------+----------|
| {date} | Created durable research artifact and recorded the current research pass. | research-worker | worker research pass {timestamp} |

* Objective

{description}

* Findings
{update}
* Footnotes and Glossary

- *Canonical research node* :: The tracked Org file that durably owns one coherent research question.
- *Research pass* :: One bounded evidence-gathering execution whose substantive findings must be persisted to the canonical research node.
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", required=True)
    parser.add_argument("--title", required=True)
    parser.add_argument("--description", default="")
    parser.add_argument("--finding", action="append", default=[])
    parser.add_argument("--source", action="append", default=[])
    parser.add_argument("--repository", action="append", default=[])
    parser.add_argument("--commit", action="append", default=[])
    parser.add_argument("--design-file", action="append", default=[])
    parser.add_argument("--next-action", default="")
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--draft", action="store_true")
    mode.add_argument("--final", action="store_true")
    parser.add_argument("--append", action="store_true")
    args = parser.parse_args()

    root, roam = project_root(), ensure_roam()
    project_slug = slugify(args.project)
    directory = roam / "research" / project_slug
    directory.mkdir(parents=True, exist_ok=True)
    mirror_structure(roam)

    path = directory / f"{slugify(args.title)}.org"
    if path.exists() and not args.append:
        raise SystemExit(f"refusing overwrite: {path.relative_to(root)}")
    if args.append and not path.exists():
        raise SystemExit(f"cannot append missing note: {path.relative_to(root)}")

    now = dt.datetime.now().astimezone()
    timestamp = now.isoformat(timespec="seconds")
    date = now.strftime("%Y-%m-%d")
    state = "RESEARCHING" if args.draft else "REVIEW"

    if not path.exists():
        path.write_text(
            new_research_document(
                args,
                state=state,
                timestamp=timestamp,
                date=date,
                project_slug=project_slug,
            ),
            encoding="utf-8",
        )
    else:
        text = path.read_text(encoding="utf-8")
        text = replace_or_insert_metadata(text, "last_modified", f"[{date}]")
        text = replace_or_insert_metadata(text, "status", state)
        text = append_changelog_row(
            text,
            f"| {date} | Persisted an additional research pass. | research-worker | worker research pass {timestamp} |",
        )
        text = insert_before_glossary(text, research_update(args, state, timestamp, date))
        path.write_text(text, encoding="utf-8")

    print(path.relative_to(root))
    return 0


if __name__ == "__main__":
    sys.exit(main())
