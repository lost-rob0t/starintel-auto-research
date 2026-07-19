---
name: resolve-entities
description: Decide whether records represent the same entity while preserving uncertainty.
---

# Resolve Entities

**Input:** candidate records, identifiers, relations, and supporting evidence.

**Output:** merge, link, or separate decision with rationale, confidence, and contradictions.

1. Compare stable identifiers before names or fuzzy text.
2. Record supporting and conflicting evidence.
3. Prefer reversible links when identity is uncertain.
4. Preserve aliases, source-specific identifiers, and decision history.

**Stop:** the decision is explainable and can be reversed without data loss.

**Script:** optional sibling `run.el`.
