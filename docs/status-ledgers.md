# Design Status Ledgers

`roam/.implemented` and `roam/.rejected` are append-only JSONL ledgers.

## Implemented event

```json
{
  "event_id": "uuid",
  "status": "IMPLEMENTED",
  "timestamp": "ISO-8601",
  "design_path": "roam/design/star-server/STAR-SERVER-001.org",
  "active_path": "roam/implement/star-server/STAR-SERVER-001.org",
  "summary": "What was implemented",
  "files": ["source/file.lisp"],
  "tests": ["nix flake check: passed"],
  "commits": ["sha"],
  "notes": [],
  "synced": false
}
```

## Rejected event

Rejected designs remain under `roam/design/`. Synchronization adds a rejection record and updates the latest status header without deleting the design.

## Idempotency

Each event has a UUID. `scripts/sync.py` uses that UUID in an Org status block, so repeated synchronization updates the same block instead of duplicating it.
