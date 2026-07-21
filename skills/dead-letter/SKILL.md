---
name: "dead-letter"
description: "Capture, inspect, and safely replay failed Starintel RabbitMQ deliveries."
version: "1.1.0"
author: "lost-rob0t"
category: "routing"
tags: ["starintel", "routing", "dead-letter", "replay"]
---

# Dead Letter

## Objective

Prevent poison messages and exhausted retries from looping forever, disappearing, or blocking Starintel ingest workers.

## Procedure

1. Classify failures as permanent input errors, transient dependency errors, concurrency conflicts, or internal defects.
2. Configure each durable ingest, target, and event queue with a dead-letter exchange and queue. Preserve the original exchange and routing key.
3. Bound retries by attempt count and elapsed age. Do not use unconditional `nack` with `requeue=true` as the final policy.
4. Write a dead-letter envelope containing:
   - original body bytes or immutable body reference;
   - original exchange, routing key, queue, message ID, correlation ID, and headers;
   - schema version and detected `dtype` when parsing succeeded;
   - failure class and safe error summary;
   - attempt count and first/last failure timestamps;
   - consumer and actor identity;
   - source or target document ID when available.
5. Never include credentials, authorization headers, session state, or unnecessary personal data in diagnostic fields.
6. Acknowledge the original delivery only after the dead-letter publish is confirmed or atomically guaranteed by broker topology.
7. Provide inspection commands or an API restricted to operators. Support filtering by failure class, route, actor, document type, and date.
8. Replay through the original validation and idempotency path. Do not write directly to CouchDB merely to bypass the failing consumer.
9. Allow correction of metadata or routing only as a new audited replay action; never rewrite the historical dead-letter record.
10. Record replay outcome, new message ID, operator or agent identity, and resulting document IDs.
11. Test malformed JSON, unsupported schema version, permanent validation failure, CouchDB outage, actor crash, retry exhaustion, and successful replay.

## Current Server Risk

The legacy receive macro requeues every error, while the generic consumer can skip filtered messages without acknowledgment. A dead-letter implementation is incomplete until both paths have explicit terminal outcomes.

## Exit Criteria

- Poison messages cannot loop indefinitely or stall a queue.
- Failed payloads remain inspectable with provenance and safe diagnostics.
- Replay is authorized, idempotent, and uses normal validation.
- Dead-letter and replay behavior is covered by broker-level integration tests.
