# Agent Zero Support

Run `scripts/install-agent-zero.sh /a0/usr`, select the desired StarIntel profile, and activate the repository project.

## Human-gated ADARD worker chain

Use `starintel-adard-gated` as the coordinator. It routes work through stage-specific workers and enforces human design/contract approval before implementation.

- `starintel-source-enrichment` — discover new data sources/providers and deepen existing canonical source research. Refine existing research first; create a new research node only for a genuinely new question. Never promotes research to design.
- `starintel-contract-audit` — compare current code to an already-approved contract/version and produce an evidence-backed requirement matrix. Does not implement or approve design.
- `starintel-implementation` — implement only the missing delta from an explicitly human-approved governing design/contract. Stops if approval or a design decision is missing.
- `starintel-verification` — execute tests and verify current code against the approved contract. May record implementation/conformance approval when every scoped requirement is proven, including when the code was already implemented before the run.

The coordinator does not force a research stage for every task. Existing code is inspected first, research is conditional, and no worker may auto-promote research, architecture, design, security policy, or a new contract.
