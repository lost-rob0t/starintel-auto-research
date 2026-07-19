#!/usr/bin/env python3
from __future__ import annotations

import json
import sys
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit


class PageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.anchors: set[str] = set()
        self.references: list[tuple[str, str]] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        values = dict(attrs)
        for key in ("id", "name"):
            value = values.get(key)
            if value:
                self.anchors.add(value)
        for key in ("href", "src"):
            value = values.get(key)
            if value:
                self.references.append((key, value))


def parse_html(path: Path) -> PageParser:
    parser = PageParser()
    parser.feed(path.read_text(encoding="utf-8"))
    return parser


def internal_target(site: Path, source: Path, reference: str) -> tuple[Path, str] | None:
    parsed = urlsplit(reference)
    if parsed.scheme or parsed.netloc or reference.startswith("//"):
        return None
    if parsed.scheme in {"data", "javascript", "mailto", "tel"}:
        return None

    raw_path = unquote(parsed.path)
    if not raw_path:
        target = source
    elif raw_path.startswith("/"):
        target = site / raw_path.lstrip("/")
    else:
        target = source.parent / raw_path

    target = target.resolve()
    try:
        target.relative_to(site.resolve())
    except ValueError as error:
        raise ValueError(f"link escapes site root: {reference}") from error

    if target.is_dir():
        target /= "index.html"
    return target, unquote(parsed.fragment)


def check_json_urls(site: Path, path: Path, errors: list[str]) -> None:
    data = json.loads(path.read_text(encoding="utf-8"))
    records = data.get("nodes", []) if isinstance(data, dict) else data
    for record in records:
        url = record.get("url")
        if not url:
            continue
        target = (site / unquote(urlsplit(url).path)).resolve()
        if not target.exists():
            errors.append(f"{path.relative_to(site)}: missing JSON target {url}")


def main() -> int:
    site = Path(sys.argv[1] if len(sys.argv) > 1 else "_site").resolve()
    if not site.is_dir():
        print(f"site directory does not exist: {site}", file=sys.stderr)
        return 2

    parsed_pages = {path.resolve(): parse_html(path) for path in site.rglob("*.html")}
    errors: list[str] = []

    for source, parser in parsed_pages.items():
        for attribute, reference in parser.references:
            try:
                resolved = internal_target(site, source, reference)
            except ValueError as error:
                errors.append(f"{source.relative_to(site)}: {error}")
                continue
            if resolved is None:
                continue
            target, fragment = resolved
            if not target.exists():
                errors.append(
                    f"{source.relative_to(site)}: broken {attribute}={reference!r}"
                )
                continue
            if fragment and target.suffix.lower() == ".html":
                target_parser = parsed_pages.get(target.resolve())
                if target_parser is None:
                    target_parser = parse_html(target)
                    parsed_pages[target.resolve()] = target_parser
                if fragment not in target_parser.anchors:
                    errors.append(
                        f"{source.relative_to(site)}: missing anchor "
                        f"{fragment!r} in {target.relative_to(site)}"
                    )

    for name in ("search-index.json", "graph.json"):
        path = site / name
        if not path.exists():
            errors.append(f"missing generated file: {name}")
        else:
            check_json_urls(site, path, errors)

    if errors:
        print("Broken Pages links:", file=sys.stderr)
        for error in sorted(errors):
            print(f"- {error}", file=sys.stderr)
        return 1

    print(f"Checked {len(parsed_pages)} HTML pages: all internal links resolve")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
