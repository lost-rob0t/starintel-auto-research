# Skill Index

Total skills: **136**

## Workflow

- `implement-one-design` — Select and implement exactly one active design.
- `mark-implemented` — Record an implemented design in the append-only implementation ledger.
- `mark-rejected` — Record a rejected design without deleting the canonical file.
- `sync-design-status` — Synchronize design ledgers into canonical Org records.
- `mirror-roam-structure` — Maintain identical project-directory structure across all roam trees.
- `search-roam` — Find the smallest relevant Org context.
- `save-research` — Create sourced draft or final research notes.
- `handoff-active-design` — Hand off active implementation state without hidden assumptions.

## Design

- `create-design-file` — Create a numbered, linked Org design contract.
- `review-design` — Review scope, dependencies, acceptance criteria, and risks.
- `decision-record` — Record a durable architecture decision.
- `rejected-approach` — Record why an approach was rejected and when to reconsider.
- `design-to-issues` — Split an approved design into dependency-ordered issues.
- `issue-to-design` — Convert an architectural issue into a design file.
- `design-migration` — Evolve a design while preserving implementation history.
- `design-index` — Build a bounded index of project designs.

## Documents

- `document-spec` — Define canonical Starintel document metadata and behavior.
- `document-migration` — Migrate stored documents between schema versions.
- `schema-conformance` — Verify cross-language document parity.
- `provenance` — Preserve source lineage and chain of custody.
- `attachments` — Store original and derived binary evidence safely.
- `unstructured-ingest` — Ingest HTML, PDF, email, chat, text, and transcripts.
- `entity-relation` — Model entities and first-class relations.
- `document-validation` — Validate documents at every trust boundary.

## Actors

- `actor-protocol` — Define interoperable actor messages and errors.
- `actor-manifest` — Describe actor identity, capabilities, resources, and health.
- `dataset-manifest` — Describe dataset storage, actors, and flow connections.
- `cl-gserver-router` — Use router-backed routee pools for hot local paths.
- `dispatcher-tuning` — Benchmark shared, pinned, and custom dispatchers.
- `actor-supervision` — Define restart, stop, escalation, and poison-message handling.
- `target-scheduling` — Persist and recover recurring target schedules.
- `backpressure` — Bound queues and propagate flow control.

## Routing

- `star-router` — Maintain client-facing and cross-process routing.
- `rabbitmq-routing` — Design exchanges, bindings, acknowledgments, and dead letters.
- `dead-letter` — Capture and replay exhausted or poison messages.
- `message-idempotency` — Prevent duplicate message effects.
- `capability-discovery` — Discover actor capabilities and protocol versions.
- `load-balancing` — Choose and test actor routing strategies.
- `route-observability` — Measure queue depth, latency, failures, and saturation.
- `remote-actor-security` — Secure remote actor registration and transport.

## Storage

- `star-actor-cache` — Design the Nim and LMDB cache/database layer.
- `lmdb-design` — Model LMDB keys, transactions, indexes, and recovery.
- `couchdb-design` — Model CouchDB revisions, views, conflicts, and replication.
- `event-replay` — Rebuild derived state deterministically from events.
- `data-warehouse` — Separate raw, normalized, entity, event, claim, and relation layers.
- `content-addressing` — Address evidence by cryptographic content hash.
- `retention` — Define retention, deletion, tombstones, and legal holds.
- `storage-benchmark` — Benchmark persistence throughput, latency, and recovery.

## Search

- `fulltext-index` — Design cross-dataset full-text indexing and ranking.
- `vector-index` — Design bounded semantic retrieval per dataset.
- `graph-index` — Maintain fast relation traversal from canonical documents.
- `prolog-query` — Run provenance-aware graph and rule queries.
- `search-permissions` — Filter search results before disclosure.
- `deduplication` — Detect exact, near, and semantic duplicates.
- `search-evaluation` — Evaluate ranking against fixed relevance cases.
- `search-explain` — Explain why each result matched and ranked.

## Collection

- `government-source` — Research and integrate an official government source.
- `scrapy-actor` — Build a structured public-source Scrapy actor.
- `playwright-actor` — Build an isolated browser actor for dynamic sources.
- `news-ingest` — Collect and version cited news documents.
- `social-actor` — Build an authorized social-platform collector.
- `proxy-rotation` — Manage proxy health, sessions, geography, and audit.
- `source-change` — Detect source content and layout changes.
- `scraper-harness` — Test scraper extraction, pagination, and provenance.

## Government

- `fec-ingest` — Ingest FEC candidates, committees, filings, and amendments.
- `sec-edgar` — Ingest SEC filings with CIK and accession lineage.
- `usaspending-sam` — Ingest awards, vendors, grants, and solicitations.
- `court-records` — Ingest dockets, filings, parties, and court metadata.
- `regulations-govinfo` — Ingest rules, notices, comments, bills, and publications.
- `census-labor` — Ingest demographic and economic series with vintages.
- `sanctions-enforcement` — Ingest sanctions, debarments, and enforcement actions.
- `government-catalog` — Catalog agencies, jurisdictions, identifiers, and update cadences.

## Languages

- `common-lisp` — Work safely in Starintel Common Lisp systems.
- `python` — Work safely in Starintel Python systems.
- `nim` — Work safely in Starintel Nim systems.
- `javascript` — Work safely in Starintel JavaScript systems.
- `prolog` — Work safely in Starintel Prolog systems.
- `emacs-lisp` — Work safely in Org-roam and org-ql tooling.
- `nix-flake` — Maintain reproducible Nix builds and checks.
- `c-abi` — Design stable cross-language C interfaces.

## Quality

- `test-first` — Reproduce bugs and add regression tests before fixing.
- `property-tests` — Test schema, parser, and routing invariants.
- `integration-tests` — Test real actor, queue, database, and API boundaries.
- `performance-benchmark` — Measure speedups against a controlled baseline.
- `load-test` — Find saturation, backpressure, and recovery behavior.
- `code-review` — Review for correctness, security, and data loss.
- `ci-repair` — Diagnose and minimally repair failing checks.
- `release-checklist` — Validate migrations, artifacts, rollback, and release evidence.

## Security

- `threat-model` — Model assets, trust boundaries, abuse cases, and mitigations.
- `authorization` — Design default-deny dataset and document authorization.
- `secret-handling` — Keep credentials out of code, logs, and artifacts.
- `input-validation` — Reject traversal, injection, invalid, and oversized input.
- `rate-limiting` — Protect collectors and public APIs with scoped limits.
- `audit-logging` — Record sensitive actions without leaking secrets.
- `dependency-review` — Review dependency source, license, security, and reproducibility.
- `evidence-integrity` — Hash, sign, verify, and audit evidence transformations.

## Agents

- `agent-zero-project` — Install and activate Starintel in Agent Zero.
- `agent-zero-subagents` — Delegate bounded Agent Zero subordinate work.
- `smart-tool-split` — Separate reasoning and writing from tool invocation.
- `context-minimization` — Keep agent context bounded and source-linked.
- `tool-normalization` — Normalize tool outputs before agent handoff.
- `hallucination-check` — Remove unsupported APIs, facts, and test claims.
- `model-routing` — Route reasoning and tool tasks to suitable models.
- `failure-recovery` — Recover agent workflows without repeating failed actions.

## Skills

- `skill-authoring` — Create a narrow reusable SKILL.md procedure.
- `skill-evaluation` — Compare agent performance with and without a skill.
- `prompt-adapter` — Map AGENTS.md into a native agent-system adapter.
- `skill-installation` — Install canonical skills into another agent runtime.
- `skill-versioning` — Version skill behavior and migration notes.
- `skill-deprecation` — Retire stale or harmful skill guidance.
- `skill-composition` — Combine small skills without duplicating policy.
- `skill-index` — Maintain searchable skill metadata and categories.

## Research

- `repository-recon` — Map an unfamiliar repository before editing.
- `parallel-repo-audit` — Audit disjoint Starintel repositories in parallel.
- `aleph-comparison` — Compare Aleph and OpenAleph patterns with Starintel.
- `competitive-analysis` — Compare Starintel with search and intelligence services.
- `source-citations` — Attach files, lines, commits, commands, and dated sources.
- `research-synthesis` — Separate evidence, user decisions, and inference.
- `research-draft-review` — Promote or retain a draft based on evidence completeness.
- `technology-spike` — Run a bounded experiment to answer one design question.

## Product

- `mission-alignment` — Check work against the dangerous-search-engine mission.
- `roadmap-priority` — Order work by dependency, leverage, risk, and mission value.
- `api-design` — Design versioned, authorized, rate-limited public APIs.
- `search-ux` — Design search, entity, graph, evidence, and export views.
- `pricing-model` — Model hosted pricing below equivalent API stacking.
- `investigation-export` — Export portable investigations with evidence and hashes.
- `evidence-report` — Generate a sourced analyst or legal investigation report.
- `release-notes` — Document user-visible changes and migrations.

## Git

- `branch-workflow` — Work on a focused branch without overwriting dirty work.
- `cross-repo-change` — Coordinate schema and protocol changes across repositories.
- `commit-audit` — Review only commits after a known audited baseline.
- `change-summary` — Summarize behavior, files, tests, and remaining risks.
- `conflict-resolution` — Resolve conflicts while preserving intent and history.
- `bisect-regression` — Find the first bad commit with a reproducible check.
- `commit-design-link` — Link commits and issues back to the active design.
- `publish-review` — Prepare a focused commit and review-ready change set.
