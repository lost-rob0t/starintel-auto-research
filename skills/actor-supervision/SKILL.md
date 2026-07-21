---
name: "actor-supervision"
description: "Supervise Starintel actors, workers, dependencies, and poison messages."
version: "1.1.0"
author: "lost-rob0t"
category: "actors"
tags: ["starintel", "actors", "actor-supervision", "recovery"]
---

# Actor Supervision

## Objective

Make actor failure visible and recoverable without duplicating work, blocking mailboxes, or restarting the whole Starintel service for every fault.

## Procedure

1. Define the actor's owned state, dependencies, in-flight work, checkpoint, and safe restart boundary.
2. Classify failures:
   - malformed or unsupported message;
   - poison message or deterministic code defect;
   - transient network, broker, browser, or database failure;
   - resource exhaustion or mailbox saturation;
   - dependency unavailable;
   - actor invariant violation.
3. Choose a bounded response for each class: reject, dead-letter, retry with backoff, restart actor, restart worker, escalate to parent/service, or stop intake.
4. Never retry a deterministic poison message indefinitely. Preserve its message ID, actor name, source document ID, and error class in the dead-letter record.
5. Keep blocking I/O outside the mailbox receive function. Use a bounded task or worker pool and send completion back to the actor.
6. Preserve idempotency across actor restart. A crash after persistence but before reply or acknowledgment must be safe to replay.
7. Start dependencies in order: actor system, producer, database pool, actor index, persistence actors, timers, target actor, actor-specific hooks, and consumers.
8. Register readiness only after the actor exists and any target name is registered.
9. On shutdown, stop intake, drain or requeue owned work, cancel timers, persist checkpoints, close browser/database/broker clients, and unregister health.
10. Emit actor events for start, ready, failure, restart, exhausted retry, shutdown, and dropped work through the actor event path.
11. Test receive-function exception, worker exception, dependency outage, mailbox saturation, repeated poison message, restart after persistence, and orderly shutdown.

## Current Server Constraints

`starintel-server` uses a Sento actor system and hook-driven startup. Several persistence and target paths are global variables rather than a formal supervision tree. Until a stronger supervisor exists, encode start order, restart ownership, and failure escalation explicitly in the actor manifest and tests.

## Exit Criteria

- One actor failure does not silently kill unrelated workers.
- Poison messages have a terminal, inspectable outcome.
- Restarts preserve idempotency and target registration.
- Health reflects dependency and actor readiness, not only process liveness.
- Failure and recovery are covered by deterministic tests.
