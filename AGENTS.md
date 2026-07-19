# Starintel Agent Rules

## Mission

Build a local-first intelligence system that collects authorized or public material, preserves evidence, normalizes documents, resolves entities, analyzes relations, and produces sourced intelligence products.

## Read Order

1. `AGENTS.md`
2. `roam/indexes/STAR-INDEX-000-roadmap.org`
3. The active research or design node
4. Its direct links and relevant source files

Never recursively load all of `roam/`.

## Source of Truth

- Org files under `roam/` are authoritative.
- Org-roam databases, context bundles, indexes, and graph exports are derived state.
- Preserve Org IDs, provenance, citations, and design history.
- Do not create a second research database or competing graph schema.

## Core Intelligence Cycle

Use only the operation needed:

1. `plan-investigation`
2. `collect-source`
3. `preserve-evidence`
4. `process-document`
5. `resolve-entities`
6. `analyze-intelligence`
7. `produce-intelligence`

The corresponding contracts live under `skills/`.

## Skill Rules

- Skills are compact operation contracts, not tutorials or policy dumps.
- Do not add language, framework, Git, product, or generic reasoning skills.
- Global rules belong here, not duplicated in every `SKILL.md`.
- New skills require a distinct intelligence operation with a stable input and output.

## Script Bootstrap

When a skill is repeatedly executed and its contract is stable:

1. Add `run.el` beside its `SKILL.md`.
2. Expose `star/skill-<operation>-run` as an interactive command.
3. Validate inputs and make retries safe.
4. Preserve source metadata, hashes, and output paths.
5. Add fixtures before claiming reliability.
6. Keep external tool invocation visible in Elisp.

Use Emacs commands to open, bootstrap, and run skill scripts.

## Research Workflow

- Capture raw findings in `roam/research/`.
- Create numbered designs in `roam/design/<project>/`.
- Link files and directories explicitly.
- Build bounded context with `star/research-build-context-bundle`.
- Promote one approved design with `star/research-promote-design`.
- Route web and desktop writes through validated Emacs operations.

## Evidence Rules

- Preserve original bytes before transformation.
- Never fabricate sources, authorization, confidence, test results, or evidence.
- Separate observed fact, inference, assessment, and speculation.
- Link every material claim to source spans or preserved artifacts.
- Preserve contradictory evidence and reversible entity decisions.

## Completion

Before finishing:

1. Run `star/research-validate`.
2. Run relevant ERT tests when Emacs is available.
3. Inspect `git diff --check` and `git diff --stat`.
4. Report changed behavior, exact validation performed, and unresolved risks.
