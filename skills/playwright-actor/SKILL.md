---
name: "playwright-actor"
description: "Build an isolated Starintel browser actor for dynamic OSINT sources."
version: "1.1.0"
author: "lost-rob0t"
category: "collection"
tags: ["starintel", "collection", "playwright-actor", "osint"]
---

# Playwright Actor

## Objective

Create a Starintel actor for sources that genuinely require browser execution while keeping sessions isolated, collection bounded, evidence preserved, and output schema-valid.

## Procedure

1. Confirm that static HTTP, an API, feed, or Scrapy cannot reliably collect the source. Do not use a browser merely because it is convenient.
2. Define and validate the target actor name, URL or identifier, allowed domains, navigation depth, actions, options, timeout, maximum pages, maximum downloads, and authentication profile reference.
3. Register the actor explicitly and declare its Rabbit target route when it runs out of process.
4. Create an isolated browser context per target, tenant, or authorization boundary. Never share cookies or storage across unrelated work.
5. Load credentials and saved authentication state from secret storage. Do not place them in target documents, actor events, screenshots, traces, or dead letters.
6. Use deterministic readiness conditions: response, locator, network state, or application signal. Avoid arbitrary sleeps as the primary synchronization method.
7. Enforce navigation, redirect, scheme, host, download-size, and file-destination policies before following links or saving files.
8. Preserve relevant HTML, downloads, screenshots, and trace references with source URL, retrieval time, and content hashes.
9. Extract records into an intermediate representation, then construct canonical Starintel documents and evidence relations.
10. Emit documents through `documents.new.<dtype>` and preserve correlation with the target and browser event stream.
11. Checkpoint pagination or cursor state so retries and restarts are idempotent.
12. Distinguish source change, authentication expiry, captcha, rate limit, timeout, browser crash, invalid extraction, and permanent target error.
13. Close pages, contexts, downloads, and browser processes during success, cancellation, failure, and service shutdown.
14. Test with recorded or local dynamic pages for navigation, login expiry, redirects, downloads, selector changes, timeout, crash recovery, cancellation, and duplicate replay.

## Exit Criteria

- Browser use is justified by source behavior.
- Sessions and credentials are isolated and cleaned up.
- Evidence and canonical documents remain linked to the target and source.
- Retries are bounded, checkpointed, and duplicate-safe.
- Browser failures produce actor events and dead-letter outcomes rather than leaked processes.
