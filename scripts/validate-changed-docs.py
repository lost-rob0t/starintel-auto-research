#!/usr/bin/env python3
from __future__ import annotations

import argparse
import importlib.util
import os
import sys
from datetime import date
from pathlib import Path
from types import ModuleType
from typing import Sequence


def load_validator(script_dir: Path) -> ModuleType:
    path = script_dir / "validate-docs.py"
    spec = importlib.util.spec_from_file_location("starintel_validate_docs", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"cannot load validator: {path}")
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


def in_changed_scope(problem: object, changed: set[Path], captcha_changed: bool) -> bool:
    path = Path(getattr(problem, "path")).resolve()
    document_class = str(getattr(problem, "document_class", ""))
    rule = str(getattr(problem, "rule", ""))

    if path in changed:
        return True
    if document_class in {"agent-instructions", "ci-workflow", "generated-output"}:
        return True
    if captcha_changed and (
        "captcha" in path.as_posix().lower()
        or rule.startswith("missing-captcha-index")
        or rule.startswith("captcha-index-missing:")
    ):
        return True
    return False


def main(argv: Sequence[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Gate changed StarIntel Org documents while preserving full repository audit mode"
    )
    parser.add_argument("--root", type=Path)
    parser.add_argument("--changed-since", required=True)
    parser.add_argument(
        "--audit-date",
        default=os.environ.get("STARINTEL_AUDIT_DATE", date.today().isoformat()),
    )
    args = parser.parse_args(argv)

    validator = load_validator(Path(__file__).resolve().parent)
    root = validator.repository_root(args.root)
    changed = validator.changed_files(root, args.changed_since)
    captcha_changed = any("captcha" in path.as_posix().lower() for path in changed)

    problems = validator.audit(root, args.changed_since, args.audit_date)
    scoped = [
        problem
        for problem in problems
        if in_changed_scope(problem, changed, captcha_changed)
    ]

    if scoped:
        print(
            f"changed-document audit found {len(scoped)} violation(s):",
            file=sys.stderr,
        )
        for problem in scoped:
            print(f"- {problem.format(root)}", file=sys.stderr)
        return 1

    changed_org = [
        path
        for path in changed
        if path.suffix.lower() == ".org" and validator.document_class(path, root) is not None
    ]
    print(
        f"changed-document audit passed for {len(changed_org)} changed substantive Org document(s); "
        f"full repository audit remains available via python3 scripts/validate-docs.py"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
