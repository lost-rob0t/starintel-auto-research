# Auto Research Agent Instructions

This file applies to every file under `roam/research/auto-research/` and supplements the repository-root `AGENTS.md`. The root instructions remain authoritative; this file adds stricter completion and review-readiness requirements for Auto Research documents.

## Research Maturity States

Do not treat document presence, merge status, publication, or a green build as evidence that research is complete.

Use the document status to reflect actual maturity:

- `DRAFT` — seed, backlog item, rough framing, or incomplete source collection.
- `RESEARCHING` — active investigation with unresolved source, architecture, validation, or comparison work.
- `REVIEW` — substantive research packet ready for operator review and a concrete decision.
- `BLOCKED` — further work depends on unavailable evidence, implementation results, authorization, or another unresolved dependency.

A short seed note with one or two sources and unresolved architecture questions must not be promoted to `REVIEW` merely because it has a plausible finding.

## Review-Ready Research Contract

A dedicated Auto Research document may enter `REVIEW` only when it contains enough evidence for a reviewer to make a decision without having to commission the missing research first.

Unless genuinely not applicable, a review-ready packet should include:

1. a precise research question and bounded scope;
2. method and repository/source scope;
3. current primary sources for externally changing facts;
4. a source matrix tying evidence to claims;
5. verified facts, contradictions, inferences, assumptions, and unresolved questions kept distinct;
6. comparison of credible alternatives where an architecture or provider choice is being made;
7. a concrete StarIntel mapping rather than generic industry summary;
8. explicit authority and data-ownership boundaries;
9. failure, replay, cancellation, budget, provenance, and security implications where relevant;
10. proposed schemas, messages, predicates, APIs, state machines, or other implementation contracts where the research recommends an implementation direction;
11. acceptance or validation gates that could falsify the recommendation;
12. research gaps and deferred questions;
13. the required approval table, changelog, and glossary from the root instructions.

If these are materially absent, leave the document in `DRAFT` or `RESEARCHING`.

There is no minimum byte count, but tiny notes that only state a finding and several future questions are normally seeds, not review packets. Depth is judged by evidence and decision completeness, not prose volume.

## PlantUML Requirement

Auto Research documents that describe non-trivial architecture must include at least one PlantUML diagram when a diagram materially improves reviewability.

A PlantUML diagram is required when the recommendation describes any of the following:

- three or more interacting components or services;
- actor or supervisor topology;
- canonical-versus-derived data ownership;
- ingestion, projection, reasoning, publication, or evidence flow;
- asynchronous queues, buses, workers, or event delivery;
- trust, privilege, credential, sandbox, or process-isolation boundaries;
- a state machine, retry lifecycle, lease lifecycle, or promotion workflow;
- replay, reconciliation, checkpoint, or crash-recovery paths;
- a protocol spanning multiple repositories, runtimes, or languages.

Use an Org source block so the repository publication pipeline renders and validates it:

```org
#+begin_src plantuml
@startuml
...
@enduml
#+end_src
```

Do not commit generated diagram images or manually rendered SVG/PNG output. The canonical diagram is the PlantUML source embedded in the Org document; `bash scripts/publish-pages` and `scripts/enhance-pages.py` own rendering and validation.

### Diagram Quality Rules

A required architecture diagram must reflect the actual recommendation in the surrounding text. It should label, where relevant:

- canonical stores versus disposable or derived indexes;
- actor/process/runtime boundaries;
- data and control-flow direction;
- trust or authorization boundaries;
- durable versus ephemeral state;
- replay/rebuild or reconciliation paths;
- named protocols, queues, schemas, or document classes.

Do not add a decorative diagram that omits the decision-critical boundaries.

## Auto Research Evidence Discipline

- Prefer primary specifications, official documentation, standards, source repositories, papers, and reproducible implementation evidence.
- Record retrieval dates for externally changing sources.
- Do not infer provider capability from marketing copy alone.
- Do not silently collapse contradictory sources into one conclusion.
- When a recommendation depends on current repository behavior, inspect the current tracked source and tests rather than relying on older research prose.
- When a recommendation depends on another StarIntel repository, read that repository's applicable `AGENTS.md` before treating its implementation as authoritative.

## Architecture and Expert-System Research

For logic, Prolog, expert-system, graph, evidence, and temporal research, explicitly address where applicable:

- canonical document authority;
- derived fact or index identity;
- provenance preservation;
- temporal validity versus observation time;
- contradiction handling;
- source dependence and corroboration;
- deterministic replay;
- named-query and untrusted-code boundaries;
- rule-package versioning and digest identity;
- proof or explanation output;
- resource budgets and cancellation;
- snapshot versus resident execution semantics.

A recommendation must not make an inference engine, renderer, cache, or derived projection the sole durable source of truth unless the research explicitly justifies and approves that authority change.

## Completion Check Before Requesting Human Review

Before changing an Auto Research document to `REVIEW`, verify:

- the research question is actually answered;
- the cited evidence supports the answer;
- major alternatives and contradictions are represented;
- the StarIntel-specific implementation consequences are concrete;
- required PlantUML diagrams are present and consistent with the prose;
- validation and falsification gates exist;
- unresolved gaps are explicit rather than hidden;
- approval rows remain `PENDING` unless real approval evidence exists;
- the current changelog records the material research pass.

If the reviewer would reasonably respond with “this is still just a seed” or “where is the architecture?”, the document is not ready for `REVIEW`.
