---
name: collect-source
description: Acquire one authorized source without interpreting or rewriting it.
---

# Collect Source

**Input:** investigation node, source locator, authorization, collection limits.

**Output:** raw artifact plus retrieval metadata and collection log.

1. Confirm the exact source and permitted collection method.
2. Acquire the smallest complete artifact needed.
3. Record locator, retrieval time, method, actor, and source response metadata.
4. Hand the unchanged artifact to evidence preservation.

**Stop:** the raw source is stored or the failure is recorded precisely.

**Script:** optional sibling `run.el`.
