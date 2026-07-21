---
name: "actor-manifest"
description: "Describe and register a Starintel actor's runtime contract and capabilities."
version: "1.1.0"
author: "lost-rob0t"
category: "actors"
tags: ["starintel", "actors", "actor-manifest", "registration"]
---

# Actor Manifest

## Objective

Create a durable actor contract that matches the actor's actual code, target registration, RabbitMQ bindings, outputs, resources, and health behavior.

## Manifest Fields

Define at least:

- stable actor name and protocol version;
- implementation repository, package/module, and start function;
- runtime: local Sento actor, RabbitMQ consumer, Scrapy worker, Playwright worker, or external service;
- accepted target name, operations, document types, and routing keys;
- produced document types, relations, events, and routing keys;
- required configuration and environment variables without secret values;
- concurrency, dispatcher or worker pool, mailbox/queue bounds, timeout, retry, and dead-letter policy;
- database, network, browser, file, and credential capabilities;
- health, readiness, shutdown, and checkpoint behavior;
- authorization and dataset restrictions.

## Procedure

1. Inspect the implementation and tests before writing the manifest. Never invent a capability because it is planned.
2. Choose one stable lowercase target actor name. It must match target documents, `register-actor`, API routes, Rabbit routing suffixes, and documentation.
3. For a local actor, create it under `star.actors:*sys*` and explicitly register the created actor reference with the actor index. The current `define-actor` macro adds a start hook but does not automatically register target routing.
4. For a Rabbit actor, declare the exact exchange, queue, and binding and map them to the same capability name.
5. State input and output schema versions and link to canonical fixtures.
6. Declare blocking work and the worker boundary used to keep the actor mailbox responsive.
7. Add readiness only after dependencies and registrations are complete.
8. Add graceful shutdown that stops intake, finishes or requeues owned work, persists checkpoints, and closes clients.
9. Link the actor manifest from the relevant dataset manifest and active design.
10. Add a validation test that compares manifest names, routes, required configuration, and produced types against the implementation.

## Exit Criteria

- A new operator or agent can start, target, observe, and stop the actor from the manifest.
- Every declared capability exists in code and tests.
- Actor registration and Rabbit bindings use the same stable name.
- Resource, retry, health, and authorization requirements are explicit.
- Planned behavior is marked as planned rather than represented as implemented.
