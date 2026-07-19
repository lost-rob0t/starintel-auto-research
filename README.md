# Starintel Multi-Agent System Pack

Repository-root instructions, workflow scripts, Agent Zero support, focused skills, and an Emacs/Org-roam second brain for Starintel research.

**Published second brain:** <https://lost-rob0t.github.io/starintel-auto-research/>

## Core Files

- `AGENTS.md` — canonical instructions
- `CLAUDE.md`
- `CODEX.md`
- adapters for Cursor, Windsurf, Cline, Roo, Continue, Copilot, Aider, Gemini, and generic agents
- Agent Zero profile and installer
- `skills/` — reusable `SKILL.md` packages
- `scripts/implement.py`
- `scripts/mark-design.py`
- `scripts/sync.py`
- `scripts/search.py`
- `scripts/save-research`

## Org Workflow

```bash
python scripts/sync.py
python scripts/implement.py roam/design/star-server/STAR-SERVER-001-example.org

python scripts/mark-design.py implemented \
  --summary "Added a CL-GServer round-robin router pool" \
  --file source/actors.lisp \
  --test "nix flake check: passed"

python scripts/sync.py
```

Rejected design:

```bash
python scripts/mark-design.py rejected \
  --reason "The design duplicates Star Router responsibilities" \
  --evidence "Repository architecture review" \
  --replacement "Use CL-GServer only for in-process routee pools"

python scripts/sync.py
```

`sync.py` preserves the canonical design, writes an implementation or rejection record into it, updates status headers, mirrors directory structure, and clears only the active working copy.

## Org-roam Pages

The checked-in `roam/` tree is the knowledge source. Emacs builds an Org-roam database from it, exports linked HTML pages with backlinks, emits search and graph indexes, and deploys `_site/` through GitHub Pages.

Enable workflow publishing once with an administrator-authenticated GitHub CLI session:

```bash
bash scripts/configure-pages
```

That command creates or updates the Pages site with `build_type=workflow` and triggers the deployment workflow on `main`. The ordinary workflow token cannot perform this initial repository-setting change.

Build and validate locally:

```bash
bash scripts/publish-pages
python3 scripts/check-pages-links.py _site
```

Interactive commands are provided by `lisp/starintel/second-brain.el`:

- `M-x star/roam`
- `M-x star/roam-capture`
- `M-x star/roam-sync`
- `M-x star/pages-build`
- `M-x star/pages-open`

## Kindle EPUB

The EPUB is an additional read-only edition for reviewing the complete Org-roam corpus on a Kindle. It does not replace or modify the website, Org files, or Org-roam database.

```bash
bash scripts/build-epub
```

The local output is `_exports/starintel-second-brain.epub`. The independent **Kindle EPUB** GitHub Actions workflow builds the same file, validates it with EPUBCheck, and uploads it as the `starintel-kindle-epub` workflow artifact.

## Agent Zero

```bash
scripts/install-agent-zero.sh /a0/usr
```

See `docs/status-ledgers.md`, `docs/skill-index.md`, and `docs/agent-compatibility.md`.
