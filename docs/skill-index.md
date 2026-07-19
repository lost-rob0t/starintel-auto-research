# Core Intelligence Operations

The skill pack contains **7** operations.

| Operation | Input | Output |
|---|---|---|
| `plan-investigation` | Question, target, authorization, constraints | Bounded investigation plan |
| `collect-source` | Plan and source locator | Raw artifact and retrieval metadata |
| `preserve-evidence` | Raw artifact | Immutable evidence record and hashes |
| `process-document` | Preserved evidence | Canonical documents and source-linked extraction |
| `resolve-entities` | Candidate records and evidence | Reversible identity decisions |
| `analyze-intelligence` | Question, documents, graph | Findings, hypotheses, contradictions, gaps |
| `produce-intelligence` | Verified findings and audience | Sourced report or investigation export |

Each directory may gain a sibling `run.el` when the operation is stable enough to automate. Generic development guidance belongs in code, tests, design files, or `AGENTS.md`—not additional skills.
