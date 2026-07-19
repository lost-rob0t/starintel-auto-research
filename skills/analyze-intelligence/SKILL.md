---
name: analyze-intelligence
description: Answer an intelligence question from sourced documents and graph relations.
---

# Analyze Intelligence

**Input:** investigation question, canonical documents, entities, relations, and provenance.

**Output:** findings, hypotheses, confidence, contradictions, graph paths, and remaining gaps.

1. Retrieve only evidence relevant to the stated question.
2. Separate observed facts, inference, and speculation.
3. Test alternative explanations and contradictory evidence.
4. Record the proof path or source set for each finding.

**Stop:** findings are supported, uncertainty is explicit, and collection gaps are actionable.

**Script:** optional sibling `run.el`.
