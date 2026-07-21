---
name: "schema-conformance"
description: "Verify Python, Common Lisp, Nim, JavaScript, and server document parity."
version: "1.1.0"
author: "lost-rob0t"
category: "documents"
tags: ["starintel", "documents", "schema-conformance", "fixtures"]
---

# Schema Conformance

## Objective

Prove that every maintained Starintel document implementation reads and writes the same wire contract.

## Current Baseline

The maintained repositories are not automatically equivalent. Python and Common Lisp currently declare document version `0.8.0`; Nim and JavaScript currently declare `0.7.3`. The server expects CouchDB `_id` and camelCase ordinary fields. Treat this drift as a failing condition, not as permission to choose whichever output is convenient.

## Procedure

1. Create canonical JSON fixtures outside any one language implementation.
2. Cover at least:
   - base document metadata;
   - target and options;
   - relation and predicate;
   - person, organization, and user;
   - email, phone, address, domain, host, URL, and network;
   - message and social-media post;
   - optional `_rev`, empty lists, booleans, Unicode, and nested objects.
3. Freeze timestamps and deterministic ID inputs in fixtures. Validate ULID shape rather than expecting separately generated ULIDs to match.
4. For each language, test constructor to JSON, JSON to object, and JSON round-trip output.
5. Normalize only JSON object ordering. Do not normalize away field-name, type, null, list, boolean, or numeric differences.
6. Compare canonical wire names exactly. Ordinary metadata must be `dateAdded` and `dateUpdated`; CouchDB keys remain `_id` and `_rev`.
7. Test deterministic identifiers using the same ordered fields, UTF-8 bytes, concatenation rule, and hash representation.
8. Run fixtures through `starintel-server` `from-json` and `as-json`, then compare the result with the canonical fixture.
9. Test CouchDB storage and retrieval so `_rev` appears only when CouchDB supplies it.
10. Fail the suite when one implementation adds, drops, renames, stringifies, or changes a field without a versioned migration.

## Known Traps to Detect

- Python instance metadata methods must mutate the instance, not the class.
- Python timestamp defaults must be evaluated per instance.
- Nim must not emit snake_case wire metadata when the server and other implementations use camelCase.
- Common Lisp list values must remain JSON arrays rather than JSON strings.
- JavaScript defaults must distinguish an intentionally false or zero value from a missing value.
- Relation constructors must preserve `predicate` and `note` as separate fields.

## Exit Criteria

- The same fixtures pass in all four spec repositories and the server.
- The declared version and emitted wire contract agree.
- Conformance runs in continuous integration and blocks incompatible releases.
- Every intentional difference has a documented migration and compatibility test.
