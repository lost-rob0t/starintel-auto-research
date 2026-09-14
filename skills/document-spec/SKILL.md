---
name: "document-spec"
description: "Create or change Starintel document types across every maintained schema implementation."
version: "1.2.0"
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
- `lost-rob0t/starintel-gpt-auto-dig` — canonical StarIntel schema/release bundle and release bump tooling.

## Procedure

1. Read the base document implementation in all four spec repositories before editing a subtype.
2. Resolve the active StarIntel release from a current consumer `schema/starintel-schema.lock.json` and its pinned canonical manifest. If the reusable `starintel-spec-version` skill is installed, use it. Never infer the active release from a `starintel-doc-v0.9.0.*` filename, stale issue prose, old research, or memory. The additive v0.9 base schema may remain `schema_version = 0.9.0` while `release_version`/`profile_version` advance; the current release is `0.9.1` and the next additive release is `0.9.2`, but the live lock/script outranks this historical sentence.
3. In the canonical schema repository run `python3 scripts/schema-release.py current` and `python3 scripts/schema-release.py check` before changing schema/release metadata.
4. Preserve the base wire fields: `_id`, optional `_rev`, `dataset`, `dtype`, `sources`, `version`, `dateAdded`, and `dateUpdated`.
5. Specify every new field's wire name, type, requiredness, default, null behavior, mutability, merge behavior, and indexing use.
6. Define the identifier rule:
   - use a deterministic content or natural-key hash only for stable identity;
   - use a ULID for distinct observations, events, or edges that must coexist;
   - define the exact field order and UTF-8 encoding for deterministic hashes.
7. Add or update the class, constructor, serializer, deserializer, exports, and tests in every maintained implementation.
8. Use each language's public constructor and metadata routine. Do not hand-build base metadata or use Python `asdict()` as canonical wire JSON.
9. Check `starintel-server/source/databases/couchdb.lisp`, relevant CouchDB views, actor matchers, and API routes for assumptions about field names or types.
10. Add shared canonical JSON fixtures and round-trip them through every language and the server serializer.
11. For an additive release/profile bump, use the canonical repository's `scripts/schema-release.py bump --to <next-patch>` workflow. Never hand-edit release/profile fields or rename the immutable base schema merely to match the release number. A new base schema version requires an explicit compatibility/migration decision.
12. After the canonical release is green, repin each consumer through its existing schema lock/sync workflow and run cross-language conformance before claiming support for the new release.

## Required Checks

- Canonical JSON uses camelCase for ordinary fields and preserves CouchDB `_id` and `_rev` names.
- Required fields fail clearly instead of receiving misleading empty defaults.
- Mutable timestamps are generated per instance, not at module import or class definition time.
- Constructors set `dtype`, dataset, timestamps, and ID on the instance.
- Existing stored documents remain readable or have an explicit migration.
- Consumer locks agree with the pinned canonical manifest on `release_version` and `schema_version`.
- No release/profile bump was performed with ad hoc text replacement.

## Exit Criteria

- All maintained implementations emit equivalent canonical JSON.
- Server ingestion, storage, search, views, and actor matching accept the new type.
- Cross-language fixtures and type-specific tests pass.
- No source, confidence, authorization, or evidence metadata was fabricated.
