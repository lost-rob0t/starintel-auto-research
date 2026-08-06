---
name: "sync-design-status"
description: "Synchronize design ledgers into canonical Org records."
version: "1.0.0"
author: "lost-rob0t"
category: "workflow"
tags: ["starintel", "workflow", "sync-design-status"]
---

# Sync Design Status

## Objective

Synchronize design ledgers into canonical Org records.

## Preconditions

- Read the applicable `AGENTS.md`.
- Identify the active design for each relevant project and its direct dependencies.
- Inspect Git status before writing.
- Do not bulk-load `roam/`.

## Procedure

1. Search the repository and Org database for existing contracts and APIs.
2. State the exact outcome and validation required.
3. Run `scripts/sync.py`; verify each canonical Org file contains its event block and latest status header, each ledger event is synced, and only active copies with synchronized events are cleared.
4. Run the narrowest meaningful validation, then broader configured checks.
5. Update research, design status, or implementation records as required.

## Exit Criteria

- The requested outcome is observable.
- The canonical designs and status ledgers agree.
- Directory mirroring and every per-project implementation slot remain valid.
- Tests or checks are reported with exact observed results.
- No unrelated files, secrets, unsupported claims, or hidden assumptions were introduced.
