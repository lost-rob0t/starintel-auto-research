---
name: "design-to-issues"
description: "Split an approved design into dependency-ordered issues."
version: "1.0.0"
author: "lost-rob0t"
category: "design"
tags: ["starintel", "design", "design-to-issues"]
---

# Design To Issues

## Objective

Split an approved design into dependency-ordered issues.

## Preconditions

- Read the applicable `AGENTS.md`.
- Identify the active design and its direct dependencies.
- Inspect Git status before writing.
- Do not bulk-load `roam/`.

## Procedure

1. Search the repository and Org database for existing contracts and APIs.
2. State the exact outcome and validation required.
3. Apply the `design-to-issues` procedure to the active design, preserve project boundaries and provenance, and make the smallest validated change.
4. Run the narrowest meaningful validation, then broader configured checks.
5. Update research, design status, or implementation records as required.

## Exit Criteria

- The requested outcome is observable.
- The canonical design and status ledgers agree.
- Directory mirroring and the one-design slot remain valid.
- Tests or checks are reported with exact observed results.
- No unrelated files, secrets, unsupported claims, or hidden assumptions were introduced.
