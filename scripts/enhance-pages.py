#!/usr/bin/env python3
"""Render PlantUML blocks and inject progressive site enhancements."""

from __future__ import annotations

import argparse
import html
import re
import shutil
import subprocess
import sys
from pathlib import Path

PLANTUML_BLOCK_RE = re.compile(
    r'<div class="org-src-container">\s*'
    r'(?P<label><label[^>]*>.*?</label>\s*)?'
    r'<pre class="src src-plantuml"[^>]*>(?P<source>.*?)</pre>\s*'
    r'</div>',
    re.DOTALL,
)
TAG_RE = re.compile(r"<[^>]+>")
XML_DECLARATION_RE = re.compile(r"\A\s*<\?xml[^>]*>\s*", re.IGNORECASE)
DOCTYPE_RE = re.compile(r"\A\s*<!DOCTYPE.*?>\s*", re.IGNORECASE | re.DOTALL)
IMPLICIT_COMPONENT_TARGET_RE = re.compile(
    r'(?m)^(?P<prefix>\s*[A-Za-z_][A-Za-z0-9_]*\s+-->\s+)'
    r'"(?P<label>[^"\n]+)"\s*$'
)


def decode_source(fragment: str) -> str:
    """Convert Org's highlighted HTML source back into PlantUML text."""
    without_tags = TAG_RE.sub("", fragment)
    return html.unescape(without_tags).strip() + "\n"


def normalize_plantuml(source: str) -> str:
    """Normalize shorthand that newer PlantUML versions reject.

    Component diagrams historically accepted relations from an alias to an
    undeclared quoted label, such as ``Control --> "Ingress"``. Current
    PlantUML treats that form as a syntax error. Bracket component notation is
    equivalent and remains portable: ``Control --> [Ingress]``.
    """

    def replace(match: re.Match[str]) -> str:
        return f"{match.group('prefix')}[{match.group('label')}]"

    return IMPLICIT_COMPONENT_TARGET_RE.sub(replace, source)


def render_plantuml(source: str, executable: str) -> str:
    """Render one PlantUML source string to inline SVG."""
    result = subprocess.run(
        [executable, "-charset", "UTF-8", "-tsvg", "-pipe"],
        input=source,
        text=True,
        capture_output=True,
        check=False,
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or "unknown PlantUML error"
        raise RuntimeError(message)

    svg = XML_DECLARATION_RE.sub("", result.stdout)
    svg = DOCTYPE_RE.sub("", svg).strip()
    start = svg.find("<svg")
    if start < 0:
        raise RuntimeError("PlantUML returned no SVG document")
    return svg[start:]


def diagram_html(source: str, svg: str) -> str:
    """Build accessible rendered-diagram markup while retaining the source."""
    escaped_source = html.escape(source.rstrip())
    return (
        '<figure class="uml-diagram" data-diagram-language="plantuml">\n'
        '  <div class="uml-diagram-canvas" role="img" aria-label="Rendered PlantUML diagram">\n'
        f"{svg}\n"
        "  </div>\n"
        "  <details class=\"uml-diagram-source\">\n"
        "    <summary>PlantUML source</summary>\n"
        f"    <pre><code>{escaped_source}</code></pre>\n"
        "  </details>\n"
        "</figure>"
    )


def inject_assets(document: str) -> str:
    """Load enhancement CSS and JS next to the existing static assets."""
    if "enhancements.css" not in document:
        match = re.search(r'<link rel="stylesheet" href="([^"]*assets/)site\.css">', document)
        if match:
            asset_base = match.group(1)
            addition = f'\n<link rel="stylesheet" href="{asset_base}enhancements.css">'
            document = document[: match.end()] + addition + document[match.end() :]

    if "enhancements.js" not in document:
        match = re.search(r'<script defer src="([^"]*assets/)site\.js"></script>', document)
        if match:
            asset_base = match.group(1)
            addition = f'\n<script defer src="{asset_base}enhancements.js"></script>'
            document = document[: match.end()] + addition + document[match.end() :]

    return document


def enhance_file(path: Path, executable: str) -> int:
    document = path.read_text(encoding="utf-8")
    rendered = 0

    def replace(match: re.Match[str]) -> str:
        nonlocal rendered
        source = decode_source(match.group("source"))
        render_source = normalize_plantuml(source)
        try:
            svg = render_plantuml(render_source, executable)
        except RuntimeError as error:
            raise RuntimeError(f"{path}: PlantUML render failed: {error}") from error
        rendered += 1
        return diagram_html(render_source, svg)

    document = PLANTUML_BLOCK_RE.sub(replace, document)
    document = inject_assets(document)
    path.write_text(document, encoding="utf-8")
    return rendered


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("site", type=Path, help="Generated site directory")
    parser.add_argument(
        "--plantuml",
        default=shutil.which("plantuml"),
        help="PlantUML executable (default: resolve from PATH)",
    )
    args = parser.parse_args()

    if not args.site.is_dir():
        parser.error(f"site directory does not exist: {args.site}")
    if not args.plantuml:
        parser.error("PlantUML is required but was not found on PATH")

    total = 0
    try:
        for path in sorted(args.site.rglob("*.html")):
            total += enhance_file(path, args.plantuml)
    except RuntimeError as error:
        print(error, file=sys.stderr)
        return 1

    print(f"Rendered {total} PlantUML block(s) across {args.site}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
