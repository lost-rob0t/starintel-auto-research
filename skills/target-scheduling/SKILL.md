---
name: "target-scheduling"
description: "Create, route, persist, recover, update, and cancel Starintel targets."
version: "1.1.0"
author: "lost-rob0t"
category: "actors"
tags: ["starintel", "actors", "target-scheduling", "targets"]
---

# Target Scheduling

## Objective

Make one-shot and recurring Starintel target documents execute exactly as intended across submission, persistence, actor registration, restart, update, and cancellation.

## Target Contract

A target contains `actor`, `target`, `delay`, `recurring`, and `options` plus normal document metadata. Its deterministic ID is derived from dataset, target value, and actor name in the maintained Python and Common Lisp implementations.

## Procedure

1. Create targets with the schema constructor. Do not hand-build the deterministic ID or omit metadata.
2. Validate a stable actor name, non-empty target value, options shape, boolean `recurring`, and delay units. Require a positive delay for recurring work.
3. Register local target actors explicitly with the actor index before accepting their targets. Remote actors must have a declared Rabbit route.
4. Persist a non-transient target before acknowledging successful submission.
5. Route a one-shot target immediately once. Schedule a recurring target once and record the installed schedule identity.
6. On startup, load persisted targets, validate them, and reinstall only schedules not already represented by the recovered schedule identity.
7. Make schedule installation idempotent across repeated startup, consumer redelivery, and target replay.
8. Define update behavior using CouchDB `_rev`: changes to actor, target, delay, recurring, or options must replace the prior schedule without leaving an orphan timer.
9. Define cancellation with a tombstone or explicit status rather than silently deleting history when auditability matters.
10. Emit actor events for accepted, persisted, routed, scheduled, executed, failed, updated, cancelled, and recovered targets.
11. Test local and Rabbit actors, one-shot first delivery, recurring execution, transient targets, unknown actors, duplicate delivery, restart recovery, delay changes, cancellation, and actor outage.

## Current Server Defects the Test Must Catch

- the target loader's length comparison currently prevents normal rows from being returned;
- `sumbit-target` and `submit-target` are inconsistently named;
- first-time local non-recurring targets can fail to route;
- repeated startup can install duplicate timers without a durable schedule identity.

Do not write a skill or test that assumes these paths already work.

## Exit Criteria

- One-shot targets run once and recurring targets run at the declared cadence.
- Restart recovery neither loses nor duplicates schedules.
- Unknown or unavailable actors produce an explicit retry or rejection.
- Updates and cancellations remove superseded timers.
- Target lifecycle events and integration tests prove the behavior.
