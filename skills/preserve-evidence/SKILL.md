---
name: preserve-evidence
description: Preserve raw material with integrity, provenance, and transformation history.
---

# Preserve Evidence

**Input:** raw artifact and collection metadata.

**Output:** immutable evidence record, content hash, provenance, and derived-file links.

1. Store the original bytes before transformation.
2. Compute and record cryptographic hashes.
3. Record source, timestamps, collector, authorization, and custody events.
4. Link every derived artifact back to the preserved original.

**Stop:** integrity can be independently verified and no provenance field is invented.

**Script:** optional sibling `run.el`.
