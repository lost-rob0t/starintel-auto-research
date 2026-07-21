---
name: "rabbitmq-routing"
description: "Implement Starintel RabbitMQ exchanges, bindings, delivery outcomes, and target routes."
version: "1.1.0"
author: "lost-rob0t"
category: "routing"
tags: ["starintel", "routing", "rabbitmq-routing", "ingest"]
---

# RabbitMQ Routing

## Objective

Route Starintel documents, targets, and actor events through RabbitMQ with durable topology and explicit acknowledgment behavior.

## Current Wire Topology

- document exchange: `documents`, topic exchange;
- new document key: `documents.new.<dtype>` and binding `documents.new.#`;
- new target key: `documents.new.target.<actor>`;
- actor target key used by the local target router: `actors.<actor>.new-target`;
- event exchange and binding: `events` with `event.#`;
- legacy queue names include `injest` and `injest-targets`.

Treat these as compatibility contracts. Correct the `injest` spelling only through a declared dual-binding migration.

## Procedure

1. Document the producer, exchange, routing key, queue, consumer, payload schema, durability, retry, and dead-letter policy.
2. Declare exchanges and queues durably before consuming or publishing.
3. Set bounded prefetch according to measured worker capacity. Do not treat prefetch as worker count.
4. Publish canonical UTF-8 JSON with Rabbit properties for document type, schema version, message ID, correlation ID, content type, and attempt when available.
5. Validate the body and verify that property type, routing suffix, and body `dtype` agree.
6. Give every delivery exactly one terminal outcome:
   - acknowledge after all required side effects succeed;
   - acknowledge an intentional, audited drop;
   - reject without requeue for permanent invalid input and route it to a dead-letter exchange;
   - reject with bounded retry for transient infrastructure failure.
7. Never use a filter predicate that skips the handler and therefore skips acknowledgment. The current generic consumer path requires this to be handled explicitly.
8. Keep one owned connection/channel lifecycle per consumer worker or a documented safe pool. Reconnect deliberately and redeclare topology after connection loss.
9. Make publishing thread-safe and confirm delivery when the producer's result matters.
10. Test wildcard bindings, target actor suffixes, transient documents, malformed JSON, consumer crashes, reconnects, duplicate delivery, and dead-letter routing.

## Required Server Review

Inspect `source/consumers/consumers.lisp`, `source/producers/producers.lisp`, `source/rabbit.lisp`, `source/frontends/http-api.lisp`, and event consumers together. Do not add a route in only one layer.

## Exit Criteria

- Every delivery is acknowledged, retried within policy, or dead-lettered.
- Queue names and routing keys match producers and consumers exactly.
- Restarting RabbitMQ or the server does not lose topology or silently stop consumption.
- Duplicate delivery is safe under the message-idempotency contract.
