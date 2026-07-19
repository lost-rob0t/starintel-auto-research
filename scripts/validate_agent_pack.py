#!/usr/bin/env python3
from __future__ import annotations
import json
import py_compile
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

def run(args: list[str], cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=cwd, check=True, capture_output=True, text=True)

def validate_static() -> None:
    required = [
        "AGENTS.md", "CLAUDE.md", "CODEX.md", "GEMINI.md",
        ".codex/config.toml", "scripts/implement.py",
        "scripts/mark-design.py", "scripts/sync.py",
        "scripts/search.py", "scripts/save-research.py",
        "agent-zero/usr/agents/starintel/prompts/agent.system.main.specifics.md",
    ]
    missing = [p for p in required if not (ROOT / p).is_file()]
    if missing:
        raise SystemExit(f"missing required files: {missing}")
    for path in (ROOT / "scripts").glob("*.py"):
        py_compile.compile(str(path), doraise=True)
    manifest = json.loads((ROOT / "skills/manifest.json").read_text(encoding="utf-8"))
    if manifest["skill_count"] != 136:
        raise SystemExit(f"unexpected skill count: {manifest['skill_count']}")
    skills = list((ROOT / "skills").glob("*/SKILL.md"))
    if len(skills) != 136:
        raise SystemExit(f"expected 136 skills, found {len(skills)}")
    for path in skills:
        text = path.read_text(encoding="utf-8")
        if not text.startswith("---\n") or "\nname:" not in text or "\ndescription:" not in text:
            raise SystemExit(f"invalid skill frontmatter: {path}")

def copy_pack(target: Path) -> None:
    for item in ROOT.iterdir():
        if item.name == "__pycache__":
            continue
        dest = target / item.name
        if item.is_dir():
            shutil.copytree(item, dest)
        else:
            shutil.copy2(item, dest)

def write_design(path: Path, title: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        f"""#+title: {title}
#+description: Validator design file
#+todo: TODO | DONE REJECTED

* TODO Design

Validator body.
""",
        encoding="utf-8",
    )

def validate_workflow() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        repo = Path(tmp)
        copy_pack(repo)
        run(["git", "init"], repo)
        run(["git", "config", "user.email", "test@example.invalid"], repo)
        run(["git", "config", "user.name", "Test"], repo)

        design1 = repo / "roam/design/star-server/STAR-SERVER-001-validator.org"
        write_design(design1, "STAR-SERVER-001 Validator")
        run([sys.executable, "scripts/sync.py"], repo)

        for tree in ("research", "implement", "indexes"):
            expected = repo / "roam" / tree / "star-server"
            if not expected.is_dir():
                raise SystemExit(f"missing mirrored directory: {expected}")

        run([sys.executable, "scripts/implement.py", str(design1.relative_to(repo))], repo)
        active1 = repo / "roam/implement/star-server/STAR-SERVER-001-validator.org"
        if not active1.is_file():
            raise SystemExit("implementation path was not preserved")

        run([
            sys.executable, "scripts/mark-design.py", "implemented",
            "--summary", "Implemented validator behavior.",
            "--file", "source/example.lisp",
            "--test", "validator: passed",
        ], repo)
        run([sys.executable, "scripts/sync.py"], repo)

        text1 = design1.read_text(encoding="utf-8")
        if "#+status: IMPLEMENTED" not in text1:
            raise SystemExit("implemented status missing")
        if "Implemented validator behavior." not in text1:
            raise SystemExit("implementation summary missing")
        if active1.exists():
            raise SystemExit("implemented working copy was not cleared")
        implemented_records = [
            json.loads(line)
            for line in (repo / "roam/.implemented").read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        if not implemented_records or not implemented_records[-1]["synced"]:
            raise SystemExit("implemented ledger was not synchronized")

        design2 = repo / "roam/design/star-router/STAR-ROUTER-001-validator.org"
        write_design(design2, "STAR-ROUTER-001 Validator")
        run([sys.executable, "scripts/sync.py"], repo)

        for tree in ("research", "implement", "indexes"):
            expected = repo / "roam" / tree / "star-router"
            if not expected.is_dir():
                raise SystemExit(f"missing second mirrored directory: {expected}")

        run([sys.executable, "scripts/implement.py", str(design2.relative_to(repo))], repo)
        active2 = repo / "roam/implement/star-router/STAR-ROUTER-001-validator.org"
        run([
            sys.executable, "scripts/mark-design.py", "rejected",
            "--reason", "Validator rejection.",
            "--evidence", "Test evidence.",
            "--replacement", "Replacement validator design.",
        ], repo)
        run([sys.executable, "scripts/sync.py"], repo)

        text2 = design2.read_text(encoding="utf-8")
        if "#+status: REJECTED" not in text2:
            raise SystemExit("rejected status missing")
        if "Validator rejection." not in text2:
            raise SystemExit("rejection reason missing")
        if not design2.is_file():
            raise SystemExit("rejected canonical design was deleted")
        if active2.exists():
            raise SystemExit("rejected working copy was not cleared")
        rejected_records = [
            json.loads(line)
            for line in (repo / "roam/.rejected").read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]
        if not rejected_records or not rejected_records[-1]["synced"]:
            raise SystemExit("rejected ledger was not synchronized")

        run([sys.executable, "scripts/sync.py", "--check"], repo)

def main() -> int:
    validate_static()
    validate_workflow()
    print("agent pack validation passed")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
