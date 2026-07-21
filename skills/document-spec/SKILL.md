---
name: "document-spec"
description: "Create or change Starintel document types across every maintained schema implementation."
version: "1.1.0"
author: "lost-rob0t"
category: "documents"
tags: ["starintel", "documents", "document-spec", "schema"]
---

# Document Spec

## Objective

Create or change a Starintel document type without producing a Python-, Common Lisp-, Nim-, JavaScript-, or server-only schema.

## Repositories

- `lost-rob0t/starintel-doc` — Python dataclasses and constructors.
- `lost-rob0t/star-cl` — Common Lisp classes used directly by `starintel-server`.
- `lost-rob0t/starintel-doc.nim` — Nim objects and JSON conversion.
- `lost-rob0t/starintel_doc.js` — JavaScript classes and constructors.
- `lost-rob0t/starintel-server` — JSON serialization, CouchDB views, RabbitMQ routing, actors, and HTTP consumers of the schema.

## Procedure

1. Read the base document implementation in all four spec repositories before editing a subtype.
2. Resolve the active schema version. Do not silently mix the currently observed `0.8.0` Python/Common Lisp contract with `0.7.3` Nim/JavaScript output.
3. Preserve the base wire fields: `_id`, optional `_rev`, `dataset`, `dtype`, `sources`, `version`, `dateAdded`, and `dateUpdated`.
4. Specify every new field's wire name, type, requiredness, default, null behavior, mutability, merge behavior, and indexing use.
5. Define the identifier rule:
   - use a deterministic content or natural-key hash only for stable identity;
   - use a ULID for distinct observations, events, or edges that must coexist;
   - define the exact field order and UTF-8 encoding for deterministic hashes.
6. Add or update the class, constructor, serializer, deserializer, exports, and tests in every maintained implementation.
7. Use each language's public constructor and metadata routine. Do not hand-build base metadata or use Python `asdict()` as canonical wire JSON.
8. Check `starintel-server/source/databases/couchdb.lisp`, relevant CouchDB views, actor matchers, and API routes for assumptions about field names or types.
9. Add shared canonical JSON fixtures and round-trip them through every language and the server serializer.
10. Bump the document version only with migration notes and a compatibility decision.

## Required Checks

- Canonical JSON uses camelCase for ordinary fields and preserves CouchDB `_id` and `_rev` names.
- Required fields fail clearly instead of receiving misleading empty defaults.
- Mutable timestamps are generated per instance, not at module import or class definition time.
- Constructors set `dtype`, dataset, timestamps, and ID on the instance.
- Existing stored documents remain readable or have an explicit migration.

## Exit Criteria

- All maintained implementations emit equivalent canonical JSON.
- Server ingestion, storage, search, views, and actor matching accept the new type.
- Cross-language fixtures and type-specific tests pass.
- No source, confidence, authorization, or evidence metadata was fabricated.
