---
name: "scrapy-actor"
description: "Build a Starintel Scrapy collector that receives targets and emits canonical documents."
version: "1.1.0"
author: "lost-rob0t"
category: "collection"
tags: ["starintel", "collection", "scrapy-actor", "osint"]
---

# Scrapy Actor

## Objective

Create a bounded structured-web collector whose Scrapy spider is controlled by a Starintel target actor and whose outputs are valid, traceable, replay-safe documents.

## Procedure

1. Define the target contract: stable actor name, target value, allowed options, scope, pagination limit, rate, timeout, and resume cursor.
2. Register the actor name explicitly with the Starintel actor index and document the matching Rabbit target route for remote execution.
3. Keep spider extraction separate from actor lifecycle and message handling. The spider parses responses; the actor validates targets, starts jobs, checkpoints, emits documents, and reports outcomes.
4. Prefer structured APIs, JSON-LD, tables, feeds, and downloadable data before brittle presentation selectors.
5. For each response, preserve source URL, retrieval time, status, relevant headers, and immutable response hash or artifact reference.
6. Normalize extracted records through Starintel schema constructors. Emit canonical JSON to `documents.new.<dtype>` with matching type properties.
7. Create source and linkage relations for extracted entities, URLs, accounts, organizations, and infrastructure. Do not infer a person or owner from a matching string alone.
8. Implement deterministic pagination and checkpointing. A restart must resume without repeating uncontrolled side effects.
9. Apply per-host concurrency, download delay, retry limits, maximum pages, maximum bytes, and explicit allowed domains.
10. Detect login walls, block pages, captchas, layout changes, empty extractions, and redirect escapes as distinct outcomes.
11. Put malformed or schema-invalid records into the normal rejection/dead-letter path with source context.
12. Test against saved responses for first page, pagination, duplicate records, missing fields, changed selectors, non-200 responses, encoding, resume, and cancellation.

## Actor Events

Emit accepted, started, page-fetched, checkpointed, document-emitted, source-changed, rate-limited, failed, cancelled, and completed events with the target and source document IDs.

## Exit Criteria

- The actor can be targeted, observed, stopped, resumed, and replayed.
- Every output is schema-valid and linked to its source response.
- Pagination and retries are bounded and idempotent.
- Saved-response tests fail when extraction silently degrades.
- Secrets, cookies, and full authenticated response bodies are not leaked into logs or events.
