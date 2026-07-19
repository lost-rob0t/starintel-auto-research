#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import subprocess
import sys
import zipfile
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ROAM = ROOT / "roam"
CACHE = ROOT / ".cache" / "epub"
DEFAULT_OUTPUT = ROOT / "_exports" / "starintel-second-brain.epub"
KIND_ORDER = {"indexes": 0, "design": 1, "research": 2, "implement": 3}
IMAGE_EXTENSIONS = {".avif", ".gif", ".jpeg", ".jpg", ".png", ".svg", ".webp"}

TITLE_RE = re.compile(r"^#\+title:\s*(.+?)\s*$", re.IGNORECASE | re.MULTILINE)
DESCRIPTION_RE = re.compile(r"^#\+description:\s*(.+?)\s*$", re.IGNORECASE | re.MULTILINE)
ID_RE = re.compile(r"^:ID:\s*(\S+)\s*$", re.IGNORECASE | re.MULTILINE)
HEADING_RE = re.compile(r"^(\*+)(\s+)", re.MULTILINE)
LINK_RE = re.compile(r"\[\[(file|id):([^\]]+)\](?:\[([^\]]*)\])?\]", re.IGNORECASE)
METADATA_RE = re.compile(
    r"^#\+(?:title|description|author|date|filetags|status|startup|options):.*$",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Note:
    path: Path
    relative: Path
    title: str
    description: str
    file_id: str | None
    anchor: str
    text: str


def die(message: str) -> "NoReturn":
    raise SystemExit(f"error: {message}")


def chapter_anchor(relative: Path) -> str:
    stem = re.sub(r"[^a-z0-9]+", "-", relative.with_suffix("").as_posix().lower()).strip("-")
    digest = hashlib.sha256(relative.as_posix().encode("utf-8")).hexdigest()[:10]
    return f"chapter-{stem}-{digest}"


def note_sort_key(path: Path) -> tuple[int, str]:
    relative = path.relative_to(ROAM)
    first = relative.parts[0] if relative.parts else ""
    return KIND_ORDER.get(first, 99), relative.as_posix().casefold()


def load_notes() -> list[Note]:
    if not ROAM.is_dir():
        die(f"missing Org-roam source directory: {ROAM}")

    paths = sorted(ROAM.rglob("*.org"), key=note_sort_key)
    if not paths:
        die("no Org files found below roam/")

    notes: list[Note] = []
    seen_ids: dict[str, Path] = {}
    for path in paths:
        text = path.read_text(encoding="utf-8")
        title_match = TITLE_RE.search(text)
        if not title_match:
            die(f"missing #+title in {path.relative_to(ROOT)}")
        description_match = DESCRIPTION_RE.search(text)
        id_match = ID_RE.search(text)
        file_id = id_match.group(1) if id_match else None
        if file_id:
            if file_id in seen_ids:
                die(
                    f"duplicate Org ID {file_id!r} in {path.relative_to(ROOT)} "
                    f"and {seen_ids[file_id].relative_to(ROOT)}"
                )
            seen_ids[file_id] = path

        relative = path.relative_to(ROAM)
        notes.append(
            Note(
                path=path,
                relative=relative,
                title=title_match.group(1).strip(),
                description=description_match.group(1).strip() if description_match else "",
                file_id=file_id,
                anchor=chapter_anchor(relative),
                text=text,
            )
        )
    return notes


def strip_leading_properties(lines: list[str]) -> list[str]:
    index = 0
    while index < len(lines) and not lines[index].strip():
        index += 1
    if index < len(lines) and lines[index].strip().upper() == ":PROPERTIES:":
        end = index + 1
        while end < len(lines) and lines[end].strip().upper() != ":END:":
            end += 1
        if end >= len(lines):
            die("unterminated leading Org property drawer")
        del lines[index : end + 1]
    return lines


def clean_body(text: str) -> str:
    lines = strip_leading_properties(text.splitlines())
    kept = [line for line in lines if not METADATA_RE.match(line)]
    body = "\n".join(kept).strip()
    return HEADING_RE.sub(lambda match: f"*{match.group(1)}{match.group(2)}", body)


def split_file_target(target: str) -> tuple[str, str | None]:
    if "::" not in target:
        return target, None
    path, search = target.split("::", 1)
    return path, search


def rewrite_links(
    note: Note,
    body: str,
    notes_by_path: dict[Path, Note],
    notes_by_id: dict[str, Note],
    unresolved: list[str],
) -> str:
    def replace(match: re.Match[str]) -> str:
        kind = match.group(1).lower()
        target = match.group(2).strip()
        label = match.group(3)

        if kind == "id":
            destination = notes_by_id.get(target)
            if not destination:
                unresolved.append(f"{note.relative}: unknown Org ID {target}")
                return label or target
            return f"[[#{destination.anchor}][{label or destination.title}]]"

        file_target, search = split_file_target(target)
        source_path = (note.path.parent / file_target).resolve()
        try:
            relative_to_root = source_path.relative_to(ROOT)
        except ValueError:
            unresolved.append(f"{note.relative}: file link escapes repository: {target}")
            return label or target

        if source_path.suffix.lower() == ".org":
            destination = notes_by_path.get(source_path)
            if not destination:
                unresolved.append(f"{note.relative}: missing Org target {relative_to_root}")
                return label or target
            anchor = destination.anchor
            if search and search.startswith("#"):
                anchor = search[1:]
            return f"[[#{anchor}][{label or destination.title}]]"

        if not source_path.exists():
            unresolved.append(f"{note.relative}: missing file target {relative_to_root}")
            return label or target

        if source_path.suffix.lower() in IMAGE_EXTENSIONS:
            return f"[[file:{source_path.as_posix()}][{label or source_path.name}]]"

        github_url = (
            "https://github.com/lost-rob0t/starintel-auto-research/blob/main/"
            + relative_to_root.as_posix()
        )
        return f"[[{github_url}][{label or source_path.name}]]"

    return LINK_RE.sub(replace, body)


def build_manuscript(notes: list[Note], destination: Path) -> None:
    notes_by_path = {note.path.resolve(): note for note in notes}
    notes_by_id = {note.file_id: note for note in notes if note.file_id}
    unresolved: list[str] = []

    parts = [
        "#+title: StarIntel Second Brain",
        "#+author: lost-rob0t",
        "#+language: en-US",
        "#+options: toc:3 num:nil",
        "",
        "This Kindle edition is an additional read-only export of the Org-roam corpus. The checked-in =roam/= tree remains the source of truth.",
        "",
    ]

    for note in notes:
        body = rewrite_links(note, clean_body(note.text), notes_by_path, notes_by_id, unresolved)
        parts.extend(
            [
                f"* {note.title}",
                ":PROPERTIES:",
                f":CUSTOM_ID: {note.anchor}",
                ":END:",
                "",
                f"/Source: =roam/{note.relative.as_posix()}=/",
                "",
            ]
        )
        if note.description:
            parts.extend([note.description, ""])
        parts.extend([body, ""])

    if unresolved:
        details = "\n".join(f"  - {item}" for item in unresolved)
        die(f"EPUB contains unresolved internal links:\n{details}")

    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text("\n".join(parts).rstrip() + "\n", encoding="utf-8")


def validate_epub_archive(path: Path) -> None:
    if not path.is_file() or path.stat().st_size == 0:
        die(f"EPUB was not created: {path}")
    with zipfile.ZipFile(path) as archive:
        bad_member = archive.testzip()
        if bad_member:
            die(f"corrupt EPUB member: {bad_member}")
        names = set(archive.namelist())
        required = {"mimetype", "META-INF/container.xml"}
        missing = sorted(required - names)
        if missing:
            die(f"EPUB is missing required members: {', '.join(missing)}")
        if archive.read("mimetype") != b"application/epub+zip":
            die("invalid EPUB mimetype")


def run_pandoc(manuscript: Path, output: Path) -> None:
    pandoc = shutil.which("pandoc")
    if not pandoc:
        die("pandoc is required; install it and rerun scripts/build-epub")

    css = ROOT / "epub" / "kindle.css"
    output.parent.mkdir(parents=True, exist_ok=True)
    command = [
        pandoc,
        str(manuscript),
        "--from=org",
        "--to=epub3",
        "--standalone",
        "--toc",
        "--toc-depth=3",
        "--split-level=1",
        f"--css={css}",
        "--metadata=title:StarIntel Second Brain",
        "--metadata=author:lost-rob0t",
        "--metadata=lang:en-US",
        f"--output={output}",
    ]
    subprocess.run(command, cwd=ROOT, check=True)
    validate_epub_archive(output)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the StarIntel Org-roam corpus as a Kindle-ready EPUB.")
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT,
        help=f"output path (default: {DEFAULT_OUTPUT.relative_to(ROOT)})",
    )
    parser.add_argument(
        "--keep-manuscript",
        action="store_true",
        help="retain the generated combined Org manuscript under .cache/epub/",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    output = args.output if args.output.is_absolute() else ROOT / args.output
    manuscript = CACHE / "starintel-second-brain.org"
    notes = load_notes()
    build_manuscript(notes, manuscript)
    run_pandoc(manuscript, output)
    if not args.keep_manuscript:
        manuscript.unlink(missing_ok=True)
    print(f"Built {output.relative_to(ROOT)} from {len(notes)} Org-roam notes.")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.CalledProcessError as error:
        print(f"error: pandoc exited with status {error.returncode}", file=sys.stderr)
        raise SystemExit(error.returncode)
