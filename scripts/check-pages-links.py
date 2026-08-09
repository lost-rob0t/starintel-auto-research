#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import sys
from dataclasses import dataclass
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import unquote, urlsplit

TEXT_SUFFIXES = {
    ".css",
    ".html",
    ".js",
    ".json",
    ".map",
    ".svg",
    ".txt",
    ".xml",
}
# StarIntel publication must use the custom domain. Third-party projects may
# legitimately publish their own documentation on GitHub Pages.
PROHIBITED_DOMAIN_RE = re.compile(
    r"(?i)(?:https?:)?//(?:www\.)?lost-rob0t\.github\.io(?:[/:?#]|$)"
)


@dataclass(frozen=True)
class SecretPattern:
    name: str
    pattern: re.Pattern[str]


SECRET_PATTERNS = (
    SecretPattern(
        "private-key-block",
        re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----"),
    ),
    SecretPattern("aws-access-key", re.compile(r"\bAKIA[0-9A-Z]{16}\b")),
    SecretPattern(
        "github-token",
        re.compile(r"\b(?:gh[pousr]_[A-Za-z0-9]{36,255}|github_pat_[A-Za-z0-9_]{50,255})\b"),
    ),
    SecretPattern(
        "slack-token",
        re.compile(r"\bxox(?:b|p|a|r|s)-[A-Za-z0-9-]{20,}\b"),
    ),
    SecretPattern("stripe-live-secret", re.compile(r"\bsk_live_[A-Za-z0-9]{20,}\b")),
    SecretPattern(
        "nonecap-live-key",
        re.compile(r"\bnc_live_[A-Za-z0-9_-]{24,}\b"),
    ),
    SecretPattern(
        "embedded-basic-auth",
        re.compile(
            r"(?i)\bhttps?://[^\s/:@]{2,64}:[^\s/@]{8,128}@[^\s/]+"
        ),
    ),
    SecretPattern(
        "unredacted-bearer-token",
        re.compile(
            r"(?i)\bAuthorization\s*:\s*Bearer\s+"
            r"(?:eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"
            r"|[A-Za-z0-9_-]{48,})\b"
        ),
    ),
)


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
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        errors.append(f"{path.relative_to(site)}: invalid JSON: {error}")
        return
    records = data.get("nodes", []) if isinstance(data, dict) else data
    if not isinstance(records, list):
        errors.append(f"{path.relative_to(site)}: expected a list of URL records")
        return
    for record in records:
        if not isinstance(record, dict):
            continue
        url = record.get("url")
        if not url:
            continue
        target = (site / unquote(urlsplit(str(url)).path)).resolve()
        if not target.exists():
            errors.append(f"{path.relative_to(site)}: missing JSON target {url}")


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def scan_generated_text(site: Path, errors: list[str]) -> int:
    scanned = 0
    for path in sorted(site.rglob("*")):
        if not path.is_file():
            continue
        if path.name not in {"CNAME", "deployment.json"} and path.suffix.lower() not in TEXT_SUFFIXES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        scanned += 1
        relative = path.relative_to(site)
        for match in PROHIBITED_DOMAIN_RE.finditer(text):
            errors.append(
                f"{relative}:{line_number(text, match.start())}: prohibited github.io publication link"
            )
        for secret in SECRET_PATTERNS:
            for match in secret.pattern.finditer(text):
                errors.append(
                    f"{relative}:{line_number(text, match.start())}: "
                    f"possible raw secret ({secret.name})"
                )
    return scanned


def validate_cname(site: Path, errors: list[str]) -> None:
    cname = site / "CNAME"
    if not cname.is_file():
        errors.append("missing generated file: CNAME")
        return
    value = cname.read_text(encoding="utf-8").strip()
    if value != "auto-research.starintel.actor":
        errors.append(
            "CNAME: expected auto-research.starintel.actor, "
            f"found {value!r}"
        )


def main() -> int:
    site = Path(sys.argv[1] if len(sys.argv) > 1 else "_site").resolve()
    if not site.is_dir():
        print(f"site directory does not exist: {site}", file=sys.stderr)
        return 2

    parsed_pages = {
        path.resolve(): parse_html(path) for path in sorted(site.rglob("*.html"))
    }
    errors: list[str] = []

    for source, parser in list(parsed_pages.items()):
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

    validate_cname(site, errors)
    scanned_files = scan_generated_text(site, errors)

    if errors:
        print("Generated Pages validation failures:", file=sys.stderr)
        for error in sorted(set(errors)):
            print(f"- {error}", file=sys.stderr)
        return 1

    print(
        f"Checked {len(parsed_pages)} HTML pages and {scanned_files} generated "
        "text files: links, custom domain, and secret scan passed"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
