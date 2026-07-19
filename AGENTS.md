# Starintel Agent Instructions

This is the canonical instruction file for every agent working in this repository.

## Mission

Build Starintel as a local-first, professional intelligence platform: a document-driven, actor-based search and analysis system that can run at home and scale into a hosted service.

Product line: **the world's most dangerous search engine**—dangerous because it can preserve, normalize, connect, and search fragmented public or authorized data while retaining evidence and provenance.

## Context Order

Read only what is needed:

1. `AGENTS.md`
2. The one active design under `roam/implement/`
3. Directly linked design and research nodes
4. Relevant source and tests
5. Git history when needed

Never recursively load all of `roam/`.

## Org Database

Every Org file must live beneath:

```text
<project-root>/roam/
```

The four trees maintain the same project-directory structure:

```text
roam/
├── design/
├── research/
├── implement/
├── indexes/
├── .implemented
└── .rejected
```

If `roam/design/star-server/` exists, these directories must also exist:

```text
roam/research/star-server/
roam/implement/star-server/
roam/indexes/star-server/
```

`scripts/sync.py` maintains this structure without deleting directories.

## One-Design Implementation Slot

`roam/implement/` may contain many empty mirrored directories, but exactly zero or one Org design file across the whole tree.

Select a design:

```bash
python scripts/implement.py roam/design/<project>/<design>.org
```

The working copy preserves the relative path:

```text
roam/design/star-server/STAR-SERVER-001.org
→ roam/implement/star-server/STAR-SERVER-001.org
```

Inspect:

```bash
python scripts/implement.py --status
```

Do not manually place a second file in `roam/implement/`.

## Completing or Rejecting a Design

Mark an implemented design:

```bash
python scripts/mark-design.py implemented \
  --summary "What was implemented" \
  --file source/example.lisp \
  --test "nix flake check: passed" \
  --commit <sha>
```

Mark a rejected design:

```bash
python scripts/mark-design.py rejected \
  --reason "Why the design was rejected" \
  --evidence "Benchmark or repository finding" \
  --replacement "Replacement design, if any"
```

Then synchronize:

```bash
python scripts/sync.py
```

The status ledgers are append-only JSONL:

- `roam/.implemented`
- `roam/.rejected`

Synchronization:

- mirrors project directories across `design`, `research`, `implement`, and `indexes`
- updates `#+status`, `#+status_event`, and `#+status_updated`
- appends an idempotent Org implementation or rejection record
- rewrites implemented designs to document what was actually implemented
- preserves rejected canonical designs and their rejection record
- removes only the active working copy after its status is synchronized
- never deletes the canonical design

A later implementation may supersede a rejection; both historical records remain in the design file and ledgers.

## Research Workflow

Search narrowly:

```bash
python scripts/search.py "router benchmark" --project star-server
```

Save research:

```bash
scripts/save-research \
  --project star-server \
  --title "CL-GServer router benchmark" \
  --draft \
  --finding "Round-robin routees improved throughput" \
  --source "benchmark output"
```

Incomplete work is `DRAFT` and tagged `:draft:`.

## Reader Accessibility and Footnote Glossary

Every design and research Org file must be readable by a person with no assumed background in intelligence work, actor systems, Common Lisp, infrastructure, security, or the specific project.

Agents must:

- define every acronym and initialism at first use
- define every technical, domain-specific, legal, intelligence, security, programming, networking, database, and project-specific term at first use
- define every non-obvious code word, package name, protocol name, component name, architectural pattern, and abbreviation
- attach an Org footnote reference to the first use of each defined term
- maintain a `* Footnotes and Glossary` section containing the plain-language definitions
- use one stable footnote label per term and reuse that label when the same term appears again
- explain terms in ordinary language before using more specialized terminology inside the definition
- define specialized words used inside a definition unless the meaning is obvious from ordinary English
- include a concrete example when a definition alone may still be unclear
- expand shortened names such as `BBP`, `SOCMINT`, `SIGINT`, `API`, `ACL`, `TLS`, `mTLS`, `URI`, `FSM`, `OTP`, `PII`, `LEO`, `ASDF`, and `CLOS`
- define project names such as Starintel, Sento, CL-GServer, Star Router, actor manifest, and dataset manifest
- never assume that a familiar term is familiar to the reader

“Every word” means every word or phrase whose meaning is not obvious to a general reader from normal English. Ordinary connective words such as “and,” “the,” and “inside” do not need glossary entries.

A design is incomplete when a reader must search outside the file merely to understand its vocabulary. External citations may support claims, but they do not replace local definitions.

Required Org structure:

```org
* Footnotes and Glossary

[fn:actor] Actor: A small independent software unit that owns its state and processes messages one at a time.

[fn:dispatcher] Dispatcher: A pool of worker threads that runs actor mailbox work.
```

## Architecture Boundaries

- `starintel-doc`, `star-cl`, `starintel-doc.nim`, `starintel_doc.js`: document specification implementations.
- `starintel-server`: Common Lisp control, ingest, search, persistence, and actor service.
- `cl-gserver`: in-process actor runtime, dispatchers, event stream, and router pools.
- `starRouter`: client-facing and cross-process routing.
- `starReplay`: deterministic replay and rebuild.
- `star-formatter`: normalization and conversion.
- `star-db-bot`: persistence actors.
- `tek9`: Star Actor Cache foundation.
- Actor Manifests describe actor capabilities.
- Dataset Manifests define declarative flows.
- Relations, provenance, and evidence are first-class documents.

## Star Server Routing

Use CL-GServer router-backed routee pools for hot in-process paths:

- validation
- normalization
- CouchDB operations
- search
- target dispatch
- attachment processing
- OCR
- entity extraction
- graph updates

Benchmark shared, pinned, and custom dispatchers before claiming a speedup. Preserve sequential message handling inside each routee. Use Star Router for client or cross-process routing; do not duplicate that boundary inside CL-GServer.

## Document Contract

When changing the document specification:

1. Update the canonical design.
2. Define type, requiredness, null behavior, mutability, merge/conflict rules, and migration.
3. Update every maintained language implementation.
4. Add shared conformance fixtures.
5. Preserve lifecycle, provenance, integrity, access, search, storage, and processing metadata.
6. Never fabricate sources, confidence, authorization, or evidence.

## Code Rules

- Make minimal, reviewable changes.
- Search existing APIs before inventing new ones.
- Validate untrusted input at boundaries.
- Keep I/O, parsing, storage, routing, and domain logic separated.
- Preserve structured errors.
- Add regression tests for bugs.
- Avoid hidden global state when an actor, manifest, or explicit dependency fits.
- Do not add dependencies without documenting why existing dependencies are insufficient.
- Never commit secrets, private datasets, generated evidence, credentials, or local state.
- Do not overwrite unrelated dirty work.
- Do not claim a command passed unless it was executed and observed.

## Multi-Agent Rules

- Delegate bounded questions, not entire projects.
- Give subagents exact scope, inputs, output format, and stop condition.
- One agent owns each writable file at a time.
- Parallelize read-only repository review and independent validation.
- The parent agent integrates decisions and validates the result.
- Limit recursive delegation by depth, time, and token budget.
- Normalize tool outputs before passing them between agents.

## Agent Zero

For Agent Zero:

- install the Starintel profile under `/a0/usr/agents/starintel`
- install skills under `/a0/usr/skills`
- activate the repository as a project
- keep Agent Zero configuration under `/a0/usr`
- keep project source and Org files inside the repository
- activate only relevant skills
- use subordinate agents for bounded read-only work
- keep synthesis, file ownership, status marking, and synchronization with the superior agent

## Git and Completion

Before editing:

```bash
git status --short
git branch --show-current
```

Before completion:

```bash
git diff --check
git diff --stat
python scripts/sync.py --check
```

Report:

- active design and final status
- files changed
- behavior changed
- tests and exact results
- research/design records updated
- unresolved risks
