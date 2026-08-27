# Starintel Multi-Agent System Pack

Repository-root instructions, workflow scripts, Agent Zero support, focused skills, and an Emacs/Org-roam second brain for Starintel research.

**Published second brain:** <https://auto-research.starintel.actor/>

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
- `scripts/validate-docs.py`
- `scripts/research_approval_migration.py`
- `scripts/search.py`
- `scripts/save-research`

## Org Workflow

```bash
python3 scripts/sync.py
python3 scripts/implement.py roam/design/star-server/STAR-SERVER-001-example.org

python3 scripts/mark-design.py implemented \
  --project star-server \
  --summary "Added a CL-GServer round-robin router pool" \
  --file source/actors.lisp \
  --test "nix flake check: passed"

python3 scripts/sync.py
```

Rejected design:

```bash
python3 scripts/mark-design.py rejected \
  --project star-server \
  --reason "The design duplicates Star Router responsibilities" \
  --evidence "Repository architecture review" \
  --replacement "Use CL-GServer only for in-process routee pools"

python3 scripts/sync.py
```

Each immediate project subtree under `roam/implement/` has its own zero-or-one active design slot. Independent projects may proceed concurrently. Use `python3 scripts/implement.py --status` to inspect every slot, and pass `--project <project>` when marking or clearing a design while multiple projects are active.

`sync.py` preserves each canonical design, writes implementation or rejection records into it, updates status headers, mirrors directory structure, and clears only active working copies whose status events were synchronized. New implementation working copies receive their own stable Org ID and link back to the canonical design.

## Repository Document Audit

Every substantive Org document is validated for stable metadata, unique IDs, resolvable Org-roam and file links, canonical approval and changelog tables, changed-file history, applicable glossary and PlantUML requirements, index coverage, generated-output boundaries, and publication policy.

```bash
python3 scripts/validate-docs.py
```

For a pull request or another material document change, validate the changed set against its real base revision:

```bash
python3 scripts/validate-docs.py \
  --changed-since origin/main \
  --audit-date "$(date -u +%F)"
```

The deterministic `--fix` mode repairs structural omissions without fabricating approval. Review its diff before committing.

Research approval migration is a separate, header-only operation. It scans the
same `roam/research/**/*.org` scope consumed by the review queue, reports the
legacy evidence mapping, and fails closed on contradictory decisions:

```bash
python3 scripts/research_approval_migration.py --dry-run
python3 scripts/research_approval_migration.py
python3 scripts/research_approval_migration.py --check --verify
```

Lifecycle remains in `#+status:`. Only an explicit human research-conclusion
decision can produce `APPROVED` or `REJECTED`; lifecycle state, publication
status, and design-promotion approval cannot do so.

## Org-roam Pages

The checked-in `roam/` tree is the knowledge source. Emacs builds an Org-roam database from it, exports linked HTML pages with backlinks, emits search and graph indexes, and deploys `_site/` through GitHub Pages.

Enable workflow publishing once with an administrator-authenticated GitHub CLI session:

```bash
bash scripts/configure-pages
```

That command creates or updates the Pages site with `build_type=workflow` and triggers the deployment workflow on `main`. The ordinary workflow token cannot perform this initial repository-setting change.

Build and validate locally with the same sequence used by continuous integration:

```bash
python3 scripts/sync.py
python3 scripts/sync.py --check
python3 scripts/validate-docs.py
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
