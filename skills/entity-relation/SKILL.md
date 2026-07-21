---
name: "entity-relation"
description: "Create Starintel entities and evidence-backed directed relations."
version: "1.1.0"
author: "lost-rob0t"
category: "documents"
tags: ["starintel", "documents", "entity-relation", "osint"]
---

# Entity Relation

## Objective

Normalize observations into reusable Starintel entities and connect them with explicit, directed, evidence-backed relation documents.

## Entity Selection

Use the narrowest existing type that preserves the observed identifier:

- `Person` and `Org` for real-world entities;
- `User` for a platform account;
- `Email` and `Phone` for contact identifiers;
- `Address` and `Geo` for locations;
- `Domain`, `Host`, `Network`, `Url`, and `Service` for infrastructure;
- `Message` and `SocialMediaPost` for communications and published content.

Do not collapse an account into a person or a domain into an organization merely because an association is suspected.

## Procedure

1. Preserve the original source document or source URL before normalization.
2. Create each endpoint entity with the public schema constructor so metadata, `dtype`, and ID rules are applied.
3. Normalize only fields required by the documented ID rule. Keep display values and source text available for evidence and later review.
4. Resolve existing deterministic-ID entities before inserting. For ULID entities, search for likely duplicates and create `same-as` or `duplicate-of` relations only when supported.
5. Create a directed relation containing `source`, `target`, `predicate`, and `note`.
6. Use the predicate vocabulary in `star-cl/src/relations.lisp` as the current allowlist. Preserve direction: `account-of` is not interchangeable with `owns`, and `links-to` is not interchangeable with `derived-from`.
7. Put the evidence reference and concise rationale in `sources` and `note`. Do not encode certainty by inventing unsupported schema fields.
8. Ensure both endpoint IDs exist or are part of the same atomic or replay-safe ingest unit.
9. Emit entities before relations through `documents.new.<dtype>`, or use a batch mechanism that reports each document result.
10. Add tests for predicate validation, direction, missing endpoints, duplicate ingest, and serialization parity.

## Implementation Warning

The Python `new_relation` helper currently accepts a `note` argument but does not expose the relation `predicate`. Do not rely on that helper for non-default predicates until it is brought into parity with the Common Lisp constructor and shared fixtures.

## Exit Criteria

- Entity documents preserve observed identifiers without unsupported attribution.
- Relation predicates are allowlisted and directionally correct.
- Every relation can be traced to evidence.
- Re-ingesting the same stable observation does not create uncontrolled duplicates.
- Graph and CouchDB relation views return the new edge as expected.
