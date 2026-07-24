from pathlib import Path

root = Path(__file__).resolve().parents[1]
changed = 0
for base in [root / "AGENTS.md", root / "research", root / "roam", root / "skills", root / "docs"]:
    paths = [base] if base.is_file() else list(base.rglob("*")) if base.is_dir() else []
    for path in paths:
        if not path.is_file() or path.suffix.lower() not in {".md", ".org", ".txt", ".json", ".yml", ".yaml"}:
            continue
        try:
            old = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        new = old.replace("***** Audit logs", "***** Optional execution logs")
        if path == root / "AGENTS.md":
            new = new.replace("provenance.\n\n\n## Capability-First Principle", "provenance.\n\n## Capability-First Principle")
        if new != old:
            path.write_text(new, encoding="utf-8")
            changed += 1

for helper in [root / ".github" / "workflows" / ".capability-first-cleanup4.yml", Path(__file__)]:
    if helper.exists():
        helper.unlink()

print(f"changed_files={changed}")
