---
name: "message-idempotency"
description: "Make Starintel document, target, event, and retry processing duplicate-safe."
version: "1.1.0"
author: "lost-rob0t"
category: "routing"
tags: ["starintel", "routing", "message-idempotency", "couchdb"]
---

# Message Idempotency

## Objective

Ensure that RabbitMQ redelivery, HTTP retry, actor restart, replay, and batch resubmission do not create unintended duplicate Starintel state or repeated side effects.

## Procedure

1. Classify the operation:
   - stable entity or observation insert;
   - distinct event or relation insert;
   - document update with `_rev`;
   - target scheduling;
   - external side effect.
2. Use the schema's documented deterministic ID for stable identity. Define normalization, field order, separators, UTF-8 encoding, and hash format exactly.
3. Use ULIDs only when separate observations must coexist. Do not generate a new ULID on every retry of the same logical message; preserve the originally assigned ID.
4. Publish a stable RabbitMQ message ID and correlation ID. Carry them through actors, event logging, dead-letter records, and replay.
5. Before a side effect, claim or record the idempotency key atomically in the system responsible for that effect.
6. On CouchDB conflict, fetch the existing document and compare canonical content:
   - equivalent content is a duplicate success;
   - differing content is a real conflict requiring update, merge, or rejection;
   - never swallow every conflict as harmless.
7. Use `_rev` for updates and reject stale revisions explicitly.
8. For relations, avoid duplicate directed edges when the same source, target, predicate, and evidence represent one logical assertion. Preserve genuinely separate observations when required.
9. For recurring targets, make startup recovery and schedule creation idempotent so a restart cannot install duplicate timers.
10. Store the original idempotency key and outcome in dead-letter and replay metadata.
11. Test duplicate HTTP requests, Rabbit redelivery before and after acknowledgment, consumer crash after persistence, conflict with different content, actor restart, and repeated replay.

## Schema Guidance

Current deterministic-ID examples include targets, organizations, users, emails, phones, domains, hosts, URLs, messages, and social posts. Persons and relations currently use ULIDs in the maintained Common Lisp/Python implementations; deduplicate them through explicit matching and relation policy rather than silently changing their ID rule in one language.

## Exit Criteria

- Repeating an accepted message produces the same durable result.
- A retry cannot repeat an external side effect without an explicit policy.
- Conflicting content remains visible and is not mislabeled as a duplicate.
- Idempotency behavior survives process and broker restarts.
