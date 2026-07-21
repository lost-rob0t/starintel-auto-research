---
name: "integration-tests"
description: "Test Starintel schema, API, RabbitMQ, actors, and CouchDB as one real flow."
version: "1.1.0"
author: "lost-rob0t"
category: "quality"
tags: ["starintel", "quality", "integration-tests", "api", "actors"]
---

# Integration Tests

## Objective

Prove behavior across the real Starintel boundaries instead of declaring success from isolated constructors or mocked route lambdas.

## Required Environment

Use isolated CouchDB and RabbitMQ instances, a test database and exchanges, the actual `starintel-server` system, and canonical document fixtures. Never point integration tests at production or personal datasets.

## Procedure

1. Start dependencies with known credentials, empty durable test queues, test CouchDB databases, and deterministic configuration.
2. Load the Common Lisp schema and server system. Start the actor system, actor index, persistence actors, producer, target timer, registered test actor, consumers, and HTTP app in documented order.
3. Run a canonical document flow:
   - submit through the ingest endpoint;
   - verify validation and Rabbit publication;
   - consume and acknowledge;
   - verify CouchDB canonical content;
   - retrieve through the document endpoint;
   - query through search or the relevant view.
4. Run a target flow:
   - create a valid target document;
   - submit it through API or RabbitMQ;
   - verify persistence and actor registration lookup;
   - verify one-shot execution or one recurring timer;
   - verify actor-event output.
5. Run duplicate and recovery cases: repeated HTTP request, Rabbit redelivery, conflict with equivalent content, conflict with different content, consumer crash after write, actor restart, server restart, and schedule recovery.
6. Run invalid cases: malformed JSON, unsupported version, unknown `dtype`, route/body mismatch, unknown actor, unauthorized dataset, oversized query, and invalid view key.
7. Run broker failure cases: connection loss, consumer restart, retry exhaustion, dead-letter creation, and authorized replay.
8. Assert HTTP statuses, response schemas, queue acknowledgment state, document count, exact stored JSON fields, event records, and absence of duplicate timers.
9. Detect duplicate method/path registrations. The existing duplicate `/dataset-size` definition must be represented by a failing regression test until fixed.
10. Tear down workers, connections, timers, test queues, and databases even after failure.

## Reporting

Report exact commands, dependency versions, commit SHAs, passed and failed cases, and retained logs or fixtures. Do not claim a boundary was tested when it was mocked.

## Exit Criteria

- Canonical documents survive the full API-to-CouchDB round trip.
- Target routing, actor execution, and event logging are proven.
- Acknowledgment, idempotency, retry, dead-letter, and restart behavior are observable.
- Authorization and validation failures prevent side effects.
- Tests run reproducibly in continuous integration.
