---
name: "actor-protocol"
description: "Define concrete Starintel messages for local Sento actors and RabbitMQ actors."
version: "1.1.0"
author: "lost-rob0t"
category: "actors"
tags: ["starintel", "actors", "actor-protocol", "messages"]
---

# Actor Protocol

## Objective

Define actor messages that remain understandable, testable, and replayable across in-process Sento actors and RabbitMQ-connected actors.

## Procedure

1. Name the operation and receiving capability. Do not make one actor infer unrelated actions from arbitrary payload shape.
2. Define a versioned envelope with the smallest required fields:
   - protocol version and operation;
   - message ID and correlation ID;
   - source actor or service;
   - dataset and authorization context reference when applicable;
   - attempt and deadline;
   - canonical document, target, document ID, or typed operation payload.
3. Use canonical JSON-compatible values for cross-process messages. Do not send Common Lisp objects, package symbols, open database clients, functions, or browser handles through RabbitMQ.
4. For local actors, keep the same semantic envelope even when represented as a plist or JSOWN object.
5. Target actors receive a validated target document containing `actor`, `target`, `delay`, `recurring`, and `options`.
6. Document actors receive a validated canonical document whose body `dtype`, Rabbit type property, and routing key agree.
7. Define reply outcomes: success, duplicate, rejected, retryable failure, permanent failure, and timeout. Include safe details and resulting document or event IDs.
8. Preserve correlation and source document IDs when emitting child documents, relations, or actor events.
9. Keep actor mailbox work bounded. Hand blocking network, browser, parser, or database operations to a worker/task boundary and return completion to the actor.
10. Add protocol fixtures and tests for decoding, unknown versions, missing fields, duplicate messages, timeout, and backward compatibility.

## Server Integration

- Local actors are created with `define-actor` or `actor-of` under `star.actors:*sys*`.
- Rabbit producers publish through `star.actors:publish` or the producer abstraction.
- Target routing uses the string actor name registered in the actor index; symbol names alone are not the protocol.
- Actor failures that exhaust retry policy must enter the dead-letter path with the original envelope.

## Exit Criteria

- The message contract is documented independently of implementation language.
- Local and remote actors process equivalent fixtures.
- Unknown operations and versions fail safely.
- Correlation, retry, and provenance survive every hop.
