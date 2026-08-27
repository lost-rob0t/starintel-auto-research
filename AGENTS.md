# Starintel Agent Instructions

This file is the repository-wide authority for every human or automated agent that reads or changes this repository.

## Instruction Scope

1. Read this root `AGENTS.md` before making any change.
2. Locate every nested `AGENTS.md` with `find .. -name AGENTS.md -print` and read the files that apply to each path you intend to edit.
3. The actual tracked tree, current source, current tests, and current scripts override remembered behavior or stale prose.
4. When inspecting another repository, read that repository's applicable `AGENTS.md` before treating its source or documentation as authoritative.
5. A narrowly scoped change should load only the active node, direct links, relevant index, source, and tests. An explicitly requested repository-wide audit is the exception: inspect the complete tracked scope required by the request.

Before editing, run and record:

```bash
git status --short
git branch --show-current
git remote -v
find .. -name AGENTS.md -print
```

Do not overwrite unrelated work. Never claim a clean tree, branch, remote, or instruction scope without observing these commands.

## Repository Mission and Boundaries

Starintel is a local-first, document-driven, actor-based intelligence platform. Research should identify technically achievable capability first; operator-selected authorization, disclosure, retention, review, and deployment policy then constrain its use. Correctness invariants—schema validation, deterministic replay, provenance, typed messages, terminal failure handling, output escaping, and reproducible publication—are mandatory.

Architecture boundaries:

- `starintel-doc`, `star-cl`, `starintel-doc.nim`, and `starintel_doc.js` implement document contracts.
- `starintel-server` owns Common Lisp control, ingest, persistence, search, authorization, and local actor services.
- `cl-gserver` owns in-process actor runtime behavior.
- Star Router owns client-facing and cross-process routing.
- Actor manifests describe runtime-discoverable actor capabilities.
- Dataset manifests describe declarative data flows.
- Relations, provenance, evidence, and operational outcomes are first-class records.

Current source and tests are authoritative over old design memory. Never invent an API because a design would be easier with it.

## Existing Scripts Are the Workflow

Inspect `scripts/`, publication code, and `.github/workflows/` before inventing a build, synchronization, validation, rendering, indexing, or publication command. Extend the current validation architecture directly; do not add a contradictory parallel framework.

The canonical source synchronization and complete-site validation sequence is:

```bash
python3 scripts/sync.py
python3 scripts/sync.py --check
python3 scripts/validate-docs.py
bash scripts/publish-pages
python3 scripts/check-pages-links.py _site
```

For a pull request or any task that materially changes substantive Org documents, also validate the changed-file history against the base revision:

```bash
python3 scripts/validate-docs.py \
  --changed-since <base-revision> \
  --audit-date YYYY-MM-DD
```

Rules:

- Run `python3 scripts/sync.py` before page generation.
- Run `python3 scripts/sync.py --check` after synchronization and before completion.
- Run `bash scripts/publish-pages`; do not invoke the lower-level Emacs exporter directly.
- `bash scripts/publish-pages` is the canonical complete-site generator. Do not manually generate selected pages.
- Run `python3 scripts/check-pages-links.py _site` against the generated complete site.
- PlantUML validation is part of `bash scripts/publish-pages`: `scripts/enhance-pages.py` renders every PlantUML block and fails the build on a rendering error. Run the complete page build whenever a diagram changes.
- Org-roam ID and link validation is performed by `scripts/validate-docs.py` and the isolated page build. Run both when Org files change.
- Continuous integration must execute the same commands in the same order. Local-only or CI-only substitute commands are defects.
- Never bypass a failing wrapper by directly invoking its implementation detail.
- Never suppress, ignore, or replace a failed exit status with a successful one.

The implementation-slot workflow remains:

```bash
python3 scripts/implement.py roam/design/<project>/<design>.org
python3 scripts/implement.py --status
python3 scripts/mark-design.py implemented --project <project> --summary <summary> --file <path> --test <observed-test>
python3 scripts/mark-design.py rejected --project <project> --reason <reason> --evidence <evidence>
python3 scripts/sync.py
```

Each immediate `roam/implement/<project>/` subtree may contain zero or one active design. Do not manually create a second active design in the same project slot. The `.implemented` and `.rejected` JSONL ledgers are append-only. Synchronization may remove an active working copy after recording its terminal state, but it must never delete the canonical design.

## Generated Files

Never hand-edit generated output.

- Do not edit `_site/`, `.cache/`, generated HTML, rendered diagram output, generated Org-roam databases, generated search indexes, or generated graph indexes.
- Do not manually copy files into `_site/`.
- Do not patch generated HTML.
- Do not commit `_site/` or `.cache/` unless this file documents a specific tracked exception. No such exception currently exists.
- Source changes must flow through tracked Org files, assets, templates, Elisp, and canonical scripts.
- The page build must remove stale output before rendering and must propagate every failed command.
- Before committing, inspect `git status --short` and `git diff --name-only` and confirm no generated cache or site output is staged.

## Substantive Org Documents

Substantive document classes include research, design, architecture, implementation, specifications, indexes, decisions, operational runbooks, projects, actors, and providers. Classify a document by its actual role; do not force unrelated factual content into one generic outline.

Every substantive Org document must contain non-empty source metadata near the beginning:

```org
:PROPERTIES:
:ID: stable-id
:END:
#+title:
#+description:
#+status:
#+filetags:
```

Requirements:

- Preserve every existing stable file ID.
- Never regenerate an ID for formatting convenience.
- New IDs must be unique and stable.
- Duplicate IDs and unresolved `id:` links are validation failures.
- Prefer durable `id:` links between canonical nodes.
- Repair stale file links and related-node links when documents move or are superseded.
- Avoid duplicate canonical research documents. Extend or supersede the existing canonical node instead.
- A superseded document must identify and link its replacement.
- New, moved, superseded, or materially changed documents require corresponding index and related-link updates.
- Expand acronyms and define technical terms on first use.
- Every materially modified substantive document must contain `* Footnotes and Glossary` with document-relevant definitions or durable links to shared definitions.

## Approval Tables

Every dedicated research, design, architecture, implementation, specification, provider, actor, and operational document requires an approval table. Indexes require their own table unless they carry an explicit metadata exemption with a concrete reason.

Use this exact header near the beginning:

```org
* Approval Table

| Approval area | Required authority | State | Evidence required | Evidence reference |
|---------------+--------------------+-------+-------------------+--------------------|
```

Allowed states are:

- `PENDING`
- `NOT STARTED`
- `APPROVED`
- `REJECTED`
- `SUPERSEDED`
- `NOT APPLICABLE`

Never fabricate approval. A merge, existing file, green build, or status keyword does not approve a research, architecture, security, operations, or implementation row. Preserve real evidence. Downgrade unsupported `APPROVED` rows. `NOT APPLICABLE` requires a written reason. Evidence references must point to real review evidence. `#+status` and approval state are separate.

An exemption must use explicit metadata such as `#+approval_exemption:` followed by a concrete reason. An empty or vague exemption is invalid.

## Changelogs

Every substantive research, design, architecture, implementation, specification, index, provider, actor, and operational document requires:

```org
* Changelog

| Date | Change | Author or actor | Evidence |
|------+--------+-----------------+----------|
```

Record material document changes. For the current task, add a dated row to every materially modified substantive document. State what changed and cite the source diff, review, fixture, command output, or other real evidence. Do not invent historical authorship, dates, or prior entries. When history cannot be established, start with the current verified change. Git history does not replace the in-document changelog.

An exemption must use `#+changelog_exemption:` with a concrete reason.

## Indexes and Canonical Documents

Every index must:

- state its scope;
- link every canonical direct child with durable `id:` links;
- avoid duplicate canonical entries;
- identify superseded documents and replacements;
- connect research, design, implementation, specifications, and operations;
- describe implementation order when order matters;
- expose approval state and known research gaps where useful.

When creating, moving, superseding, or materially changing a document, update its project index in the same change. The CAPTCHA index must cover every canonical broker, detector, challenge, solver, provider, adapter, implementation, operations, and future-work node.

## Research and Provider Contracts

Use current primary sources for externally changing facts and record retrieval dates. Separate verified facts, contradictions, inference, and unresolved questions. Provider marketing is not an API contract. Browser-extension behavior is not automatically a server API capability.

For actor or provider capability research, record exact request fields, result fields, result kind, authentication, session/network requirements, cookies, proxies, user agent, mobile requirements, delivery model, cancellation, idempotency, ambiguous submission behavior, concurrency, billing, retention, disclosure, errors, confidence, fixtures, live-probe requirements, unsupported variants, and contradictions.

Do not advertise unverified runtime capability in a static manifest. Live probes must be opt-in, credential-gated, cost-bounded, capability-specific, and restricted to operator-owned or explicitly authorized systems. Continuous integration must never call a paid provider.

## Publication and Domain Rules

The public site is `https://auto-research.starintel.actor/`.

- Use only `auto-research.starintel.actor` links when reporting published pages.
- Do not report or emit `github.io` publication links.
- Generated canonical, navigation, sitemap, asset, and internal links must not use `github.io`.
- Keep internal site links relative.
- Do not hard-code branch-preview URLs into exported pages.
- Preserve source directory structure in published note paths.
- Never claim pages were published unless the target-branch publication workflow completed successfully.
- A local `_site` build proves generation, not deployment.
- Never commit secrets, credentials, private evidence, private datasets, authorization headers, browser-session material, or raw sensitive solver results to source or generated pages.

`roam/indexes/second-brain/SECOND-BRAIN-000-org-roam-pages.org` is the canonical publishing index.

## Continuous Integration

The Pages workflow must:

1. run the canonical synchronization process;
2. run repository document validation;
3. generate the complete site with `bash scripts/publish-pages`;
4. fail on page generation or PlantUML rendering errors;
5. fail on unresolved Org-roam IDs, file links, pages, assets, or anchors;
6. fail on missing or malformed approval tables and changelogs;
7. fail on invalid approval states or unsupported approval evidence;
8. fail when materially changed substantive documents lack a current changelog entry or glossary;
9. fail when generated pages expose prohibited secret material or `github.io` links;
10. reject tracked `_site/` and `.cache/` output;
11. avoid paid provider calls;
12. deploy only from the expected target branch or an explicit manual dispatch;
13. publish with the `auto-research.starintel.actor` domain.

Do not maintain contradictory local and CI workflows.

## Code and Test Rules

- Make direct, reviewable changes; avoid workaround layers.
- Search existing APIs before adding an API or dependency.
- Validate untrusted input at boundaries.
- Preserve typed errors and terminal failure states.
- Add regression tests for bugs and validators.
- Keep I/O, parsing, storage, routing, and domain logic separated.
- Make retries idempotent and bounded.
- Never persist secrets in messages, documents, fixtures, logs, or generated pages.
- Never claim a check passed unless it was executed and its result was observed.
- Never claim a command was run when it was inferred from CI configuration or prior history.

## Research Approval Guardrails

- The durable research queue scope is `roam/research/**/*.org`, excluding only the auxiliary `index.org`, `sources.org`, and `search-log.org` files already excluded by `scripts/research_queue.py`. Do not migrate design documents, ADRs, indexes, runbooks, or ordinary notes because they contain the word “research”.
- Use `python3 scripts/research_approval_migration.py` for corpus migration. Do not hand-edit a batch of research records. The tool must remain deterministic, idempotent, header-only, and fail closed on contradictory approval evidence.
- Preserve every `#+status:` value and every research body byte-for-byte. Canonical approval fields must remain immediately after lifecycle metadata, use `prolog-rlm.research-approval.v1`, and keep lifecycle and approval as independent dimensions.
- A model or agent that discovers a new malformed approval shape, legacy table, or queue false positive must add the exact shape as a regression fixture, extend the parser or classifier and its validator, and update the GitHub Actions guard in the same change. Correcting one document without extending the guard is incomplete.
- Before migration, record `--dry-run` totals, lifecycle counts, inferred approval counts, canonical records, and every ambiguity. After migration, run `python3 scripts/research_approval_migration.py --check --verify` and prove zero unmigrated records, unchanged lifecycle fields, unchanged bodies, and zero second-pass changes.
- Approval PR discovery must use the exact `<!-- starintel-research-approval:v1 -->` body line or an explicitly documented strict legacy convention. Arbitrary occurrences of `research` or `ADARD` are never sufficient inclusion criteria.

## Git and Completion

Before completion, run and record the exact output of:

```bash
git diff --check
git diff --stat
python3 -m py_compile \
  scripts/_roamlib.py \
  scripts/implement.py \
  scripts/mark-design.py \
  scripts/sync.py \
  scripts/validate-docs.py \
  scripts/enhance-pages.py \
  scripts/check-pages-links.py
python3 -m unittest discover -s tests -p 'test_*.py' -v
python3 scripts/sync.py
python3 scripts/sync.py --check
python3 scripts/validate-docs.py
bash scripts/publish-pages
python3 scripts/check-pages-links.py _site
git status --short
git diff --name-only
```

When substantive Org files changed, also run the changed-file validation command against the actual base revision and current date.

Report:

- branch and exact head SHA;
- pull request and target branch;
- applicable `AGENTS.md` files read;
- complete tracked scope inspected;
- files created, changed, deleted, moved, or superseded;
- canonical commands executed and exact results;
- approval, changelog, metadata, Org-roam, index, PlantUML, generated-site, link, secret, and prohibited-domain results;
- unresolved risks and research gaps;
- publication workflow result and only `auto-research.starintel.actor` page links.

Do not enable auto-merge. Merge directly only after every required check for the current head is complete and green, the branch is current and mergeable, review requirements are satisfied, discussions are resolved, and the expected current head SHA is supplied to the merge operation. After merging, verify the merge commit on the target branch and verify the target-branch publication workflow.
