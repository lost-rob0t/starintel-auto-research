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
- Identify the active design and its direct dependencies.
- Inspect Git status before writing.
- Do not bulk-load `roam/`.

## Procedure

1. Search the repository and Org database for existing contracts and APIs.
2. State the exact outcome and validation required.
3. Run `scripts/sync.py`; verify the canonical Org file contains the event block and latest status header, the ledger event is synced, and the active copy is cleared.
4. Run the narrowest meaningful validation, then broader configured checks.
5. Update research, design status, or implementation records as required.

## Exit Criteria

- The requested outcome is observable.
- The canonical design and status ledgers agree.
- Directory mirroring and the one-design slot remain valid.
- Tests or checks are reported with exact observed results.
- No unrelated files, secrets, unsupported claims, or hidden assumptions were introduced.
