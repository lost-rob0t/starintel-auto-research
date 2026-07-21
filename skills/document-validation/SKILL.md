---
name: "document-validation"
description: "Validate Starintel documents at HTTP, RabbitMQ, actor, and CouchDB boundaries."
version: "1.1.0"
author: "lost-rob0t"
category: "documents"
tags: ["starintel", "documents", "document-validation", "ingest"]
---

# Document Validation

## Objective

Reject malformed or incompatible Starintel documents before they enter RabbitMQ, actor mailboxes, CouchDB, search indexes, or downstream exports.

## Validation Boundaries

Validate at every independently reachable boundary:

- HTTP request body before publishing;
- RabbitMQ consumer before side effects;
- actor message before processing or fan-out;
- CouchDB insert or update before persistence;
- import, replay, and migration tools before committing a batch.

## Procedure

1. Parse the payload as one JSON object. Reject invalid JSON, arrays where an object is expected, duplicate keys when the parser exposes them, and oversized bodies.
2. Validate base fields: `_id`, `dataset`, `dtype`, `sources`, `version`, `dateAdded`, and `dateUpdated`. Treat `_rev` as optional CouchDB revision metadata.
3. Require non-empty string identifiers, dataset names, and document types. Require integer Unix timestamps and a list of string sources.
4. Compare `dtype` against the route, RabbitMQ type property, routing key suffix, and selected schema class. Reject disagreement.
5. Reject unsupported schema versions instead of coercing them into the current version.
6. Validate type-specific required fields and nested object shapes. Do not accept empty defaults when the type cannot be meaningful without the value.
7. Apply type rules:
   - target documents require `actor` and `target`;
   - relations require existing source and target IDs plus an allowed predicate;
   - deterministic-ID types must match the documented normalization and hash rule;
   - recurring targets require a valid positive delay.
8. Return a structured result containing field path, error code, safe message, and retry classification. Do not return raw tracebacks to clients.
9. Ensure rejected or intentionally ignored RabbitMQ deliveries are explicitly acknowledged or dead-lettered. A predicate must never leave a message unacknowledged.
10. Add regression fixtures for valid, missing, wrong-type, wrong-version, path/body mismatch, oversized, and malicious inputs.

## Server-Specific Checks

- `starintel-server` currently republishes `/new/document/:dtype` and `/new/target/:actor` bodies directly. Validation must run before `basic-publish`.
- Query parameters such as `limit`, `skip`, `start_key`, `end_key`, `sort`, and `bookmark` need bounded parsing and explicit failure responses.
- CouchDB conflicts are not automatically proof that two payloads are equivalent; compare the existing canonical document before classifying a duplicate.

## Exit Criteria

- Invalid documents cannot reach persistence or actor side effects.
- Valid fixtures survive API, RabbitMQ, actor, serialization, and CouchDB round trips.
- Every failure has an explicit HTTP status or queue disposition.
- Validation behavior is tested, deterministic, and independent of language implementation.
