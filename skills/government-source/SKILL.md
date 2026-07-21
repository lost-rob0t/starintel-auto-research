---
name: "government-source"
description: "Evaluate and ingest an official government source into Starintel."
version: "1.1.0"
author: "lost-rob0t"
category: "collection"
tags: ["starintel", "collection", "government-source", "osint"]
---

# Government Source

## Objective

Turn an official public source into a documented, repeatable Starintel collection flow with stable identifiers, provenance, update handling, and schema-valid output.

## Procedure

1. Identify the authoritative agency, jurisdiction, program, dataset, publication, and official access point. Prefer a documented API or bulk download over scraping rendered pages.
2. Record source ownership, terms, access method, authentication if any, update cadence, retention window, pagination, rate limits, and historical coverage.
3. Capture representative raw responses and documentation with retrieval date and content hash.
4. Determine source identifiers and amendment semantics. Distinguish record identity from filing version, correction, cancellation, or replacement.
5. Map source fields to the narrowest Starintel document types. Do not force unlike records into one generic entity.
6. Define deterministic ID inputs from official stable identifiers when available. Keep distinct versions or observations separate when the source requires history.
7. Populate `sources` with the official record or dataset reference and create provenance relations such as `collected-from`, `derived-from`, or `observed-on` where applicable.
8. Preserve raw records or immutable source snapshots so normalized documents can be rebuilt.
9. Define incremental collection using official timestamps, cursors, sequence numbers, or release versions. Do not use local `dateAdded` as the source's update cursor.
10. Handle deletions, amendments, and source corrections explicitly; never silently overwrite evidence.
11. Validate and emit canonical documents through the normal ingest route with idempotency and dead-letter handling.
12. Test pagination, rate limiting, empty pages, schema drift, amended records, duplicate runs, interrupted resume, and source outage.

## Basic OSINT Checks

- Separate observed fact from inference.
- Record the exact official source supporting each claim.
- Do not infer identity solely from a matching name.
- Preserve jurisdiction and effective date because official records can conflict across time and agencies.
- Mark unavailable or ambiguous fields as unknown rather than fabricating values.

## Exit Criteria

- The source can be recollected and normalized from documented steps.
- Every document traces to an official record or snapshot.
- Incremental runs are idempotent and amendment-aware.
- Schema, actor, API, and storage tests cover the source flow.
