---
name: "input-validation"
description: "Validate Starintel API, queue, actor, view, and file inputs before use."
version: "1.1.0"
author: "lost-rob0t"
category: "security"
tags: ["starintel", "security", "input-validation", "api"]
---

# Input Validation

## Objective

Reject invalid, ambiguous, oversized, and dangerous inputs before they reach schema constructors, CouchDB queries, RabbitMQ, actor mailboxes, parsers, browsers, or file operations.

## Procedure

1. Define an allowlisted input schema for each boundary. Validation is not a generic truthiness check.
2. Parse JSON once and require the expected top-level type. Apply a strict body-size limit before parsing.
3. For document ingest, validate canonical base fields, supported schema version, known `dtype`, type-specific required fields, and path/body/property agreement.
4. For IDs, distinguish accepted ULIDs, deterministic hexadecimal hashes, CouchDB design IDs, and application names. Never pass arbitrary document IDs into file paths or shell commands.
5. For API integers such as `limit` and `skip`, reject non-decimal input, negatives, overflow, and values above the endpoint maximum.
6. For booleans, accept a documented representation only. Do not treat every non-empty string as true.
7. For CouchDB view keys, parse JSON deliberately and bound nesting, array length, string length, group level, and range width.
8. For search, bound query length, result count, sort fields, bookmark length, and supported syntax. Reject missing `q` when the backend requires it.
9. For actor and target names, use a stable allowlist or registered capability lookup. Do not turn untrusted strings into Lisp symbols or package names.
10. For URLs, files, and downloads, validate scheme, host policy, redirect policy, maximum bytes, content type, archive expansion, and destination containment.
11. Return explicit field errors and an appropriate HTTP or queue disposition. Do not leak parser internals or tracebacks.
12. Test empty, boundary, Unicode, wrong-type, duplicate, deeply nested, oversized, traversal, injection, unknown actor, unsupported version, and route/body mismatch inputs.

## Current Server Review Points

- `parse-integer` calls in route lambdas need guarded bounds and structured errors.
- `jsown:parse` on `start_key` and `end_key` must not accept unbounded attacker-controlled structures.
- `/new/document/:dtype` and `/new/target/:actor` currently trust the body before publishing.
- Actor routing must use the registered actor index rather than interning user input.

## Exit Criteria

- No unvalidated input reaches a side effect or dynamic dispatch boundary.
- Validation failures are deterministic and safely reported.
- Limits are documented and tested at exact boundaries.
- Validation does not silently coerce incompatible schema versions or field types.
