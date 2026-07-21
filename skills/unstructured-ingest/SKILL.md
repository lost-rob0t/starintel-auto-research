---
name: "unstructured-ingest"
description: "Convert raw HTML, PDF, email, chat, text, and transcripts into Starintel documents."
version: "1.1.0"
author: "lost-rob0t"
category: "documents"
tags: ["starintel", "documents", "unstructured-ingest", "collection"]
---

# Unstructured Ingest

## Objective

Preserve an acquired artifact and derive valid Starintel documents from it without losing provenance, source text, or replayability.

## Procedure

1. Record the acquisition source, retrieval time, media type, original name, and content hash before parsing.
2. Store or reference the immutable raw artifact. Derived text is not a replacement for the original HTML, PDF, email, chat export, transcript, image, or download.
3. Select the parser by detected content, not only by file extension or declared `Content-Type`.
4. Extract text and structured fields into an intermediate record that preserves source offsets, page numbers, message IDs, URLs, and parser warnings.
5. Map observations to existing schema types:
   - email content to `EmailMessage` and address identifiers to `Email`;
   - chat records to `Message`;
   - posts to `SocialMediaPost`;
   - discovered links to `Url`;
   - accounts to `User`;
   - people, organizations, phones, addresses, domains, and hosts to their matching types.
6. Use schema constructors and canonical JSON. Do not hand-build `_id`, `dtype`, version, or timestamp metadata.
7. Put source references in `sources` and connect derived documents to the raw artifact or source document with `extracted-from`, `derived-from`, or `downloaded-from` relations.
8. Treat `dateAdded` and `dateUpdated` as Starintel lifecycle timestamps. Preserve a source publication or message timestamp in a documented type field; open a schema change when the type lacks one instead of misusing lifecycle fields.
9. Validate every document before emitting it to `documents.new.<dtype>`.
10. Use deterministic IDs for stable observations and idempotent replay. Keep distinct observations distinct even when their normalized text matches.
11. Emit a parse summary containing accepted documents, rejected records, warnings, source hash, and relation count.
12. Add fixtures for malformed encoding, empty extraction, duplicate content, nested replies, attachments, Unicode, and partial parser failure.

## Server Constraints

`starintel-server` currently stores messages arriving on `documents.new.#`; it does not perform general document parsing. Parsing and schema creation must happen before the document reaches the generic ingest consumer unless a dedicated parser actor is explicitly introduced.

## Exit Criteria

- The original artifact remains retrievable and hash-verifiable.
- Every derived document identifies its source.
- Replaying the same artifact is safe and reports duplicates instead of multiplying them.
- Parser failures are isolated, observable, and recoverable.
- Canonical documents pass schema and server round-trip tests.
