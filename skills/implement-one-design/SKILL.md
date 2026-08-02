---
name: "implement-one-design"
description: "Select and implement one active design within a project."
version: "1.0.0"
author: "lost-rob0t"
category: "workflow"
tags: ["starintel", "workflow", "implement-one-design"]
---

# Implement One Design

## Objective

Select and implement exactly one active design within the target project while allowing independent projects to proceed concurrently.

## Preconditions

- Read the applicable `AGENTS.md`.
- Identify the target project, its active design, and direct dependencies.
- Inspect Git status before writing.
- Do not bulk-load `roam/`.

## Procedure

1. Search the repository and Org database for existing contracts and APIs.
2. State the exact outcome and validation required.
3. Verify the selected project slot is empty, use `scripts/implement.py`, preserve the design-relative path, and refuse a second active Org file inside the same project subtree.
4. Run the narrowest meaningful validation, then broader configured checks.
5. Update research, design status, or implementation records as required.

## Exit Criteria

- The requested outcome is observable.
- The canonical design and status ledgers agree.
- Directory mirroring and every per-project implementation slot remain valid.
- Tests or checks are reported with exact observed results.
- No unrelated files, secrets, unsupported claims, or hidden assumptions were introduced.
