#!/usr/bin/env python3
"""Generate reproducible source modification dates from Git history."""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path


def build_manifest(root: Path) -> dict[str, str]:
    manifest: dict[str, str] = {}
    for path in sorted((root / "roam").rglob("*.org")):
        relative = path.relative_to(root / "roam").as_posix()
        result = subprocess.run(
            ["git", "log", "-1", "--format=%cI", "--", path.relative_to(root)],
            cwd=root,
            check=True,
            capture_output=True,
            text=True,
        )
        timestamp = result.stdout.strip()
        if not timestamp:
            raise SystemExit(f"no Git modification date for {path}")
        manifest[relative] = timestamp
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[1]
    output = root / "pages" / "source-modified.json"
    manifest = build_manifest(root)
    rendered = json.dumps(manifest, indent=2, sort_keys=True) + "\n"
    if args.check:
        if not output.is_file() or output.read_text(encoding="utf-8") != rendered:
            raise SystemExit("pages/source-modified.json is stale; run scripts/source-modified-dates.py")
        print(f"source_modified_dates=PASS records={len(manifest)}")
        return 0
    output.write_text(rendered, encoding="utf-8")
    print(f"wrote {output} with {len(manifest)} records")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
