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

## Current authority

StarLang `https://github.com/lost-rob0t/star-lang/blob/765f1673851192bcaf1cdd2f35c47608f979b079/specs/starintel/0.10.1/core.star` and its generated release at immutable commit
`765f1673851192bcaf1cdd2f35c47608f979b079` own the maintained 0.10.1 contract.
Language libraries consume the generated schema and portable manifest.

## Procedure

1. Verify the pinned `release-lock.json` and every generated artifact hash.
2. Propose semantic additions in StarLang `core.star`; do not independently
   add vocabulary in Python, Lisp, Nim, JavaScript, JSON-LD, or Prolog.
3. Run upstream generation and conformance, then repin each consumer with its
   repository-owned sync tool and full immutable commit SHA.
4. Current wire documents are flat lowerCamelCase: `id`, optional `rev`,
   `dataset`, `dtype`, and `schemaVersion`. Storage adapters may translate
   CouchDB `_id` / `_rev` at the storage boundary only.
5. Preserve requiredness, missing-vs-null behavior, opaque maps, decimal-string
   types, StarReference links, deterministic identity, and provenance.
6. Treat historical nested envelopes as explicit read/migration compatibility.
   Unsupported `operation`, `investigation-target`, and `dossier` records need
   approved lossless mappings; never alias them to scheduler `target`.
7. Run exact-head shared fixtures, generated-model roundtrips, boundary rejection
   tests, and actual service tests. Report blocked languages separately.

## Required Checks

- No downstream reverse export or handwritten schema is current authority.
- No silent field dropping, collision resolution, or extension laundering.
- Hash pins and generated inventory agree across every maintained consumer.
- Legacy stored records remain readable through an explicit bounded path.

## Exit Criteria

- All maintained implementations emit equivalent canonical JSON.
- Server ingestion, storage, search, views, and actor matching accept the new type.
- Cross-language fixtures and type-specific tests pass.
- No source, confidence, authorization, or evidence metadata was fabricated.
