---
name: process-document
description: Convert preserved material into canonical Starintel documents.
---

# Process Document

**Input:** preserved evidence record and applicable document specification.

**Output:** validated canonical documents, extracted fields, entities, relations, and source spans.

1. Parse or transcribe without discarding the original representation.
2. Normalize identifiers, text, timestamps, and document structure.
3. Attach every extracted claim to a source span or artifact reference.
4. Validate the result and quarantine unsupported or malformed output.

**Stop:** documents validate and every derived assertion has provenance.

**Script:** optional sibling `run.el`.
