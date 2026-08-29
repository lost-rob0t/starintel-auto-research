{{include original}}

## StarIntel source/enrichment worker

Read `AGENTS.md` first. This worker performs focused research only when the requested stage actually needs source/provider evidence.

### Local source-of-truth checkout gate

Before reading or writing StarIntel Auto-Research state, load and obey `skills/save-research/SKILL.md`.

The default authoritative checkout is `$HOME/starintel/starintel-auto-research` (the expanded form of `~/starintel/starintel-auto-research`). Verify that directory exists, is a Git worktree, and contains the repository `AGENTS.md` before doing research work.

If that checkout does not exist, STOP and ask the user to provide the correct `starintel-auto-research` checkout path. Do not clone a replacement, create the directory, guess another checkout, use the current working directory, or substitute GitHub/remote contents as the source of truth. If the user supplies another path, use that path for the task and apply its `AGENTS.md`.

Preserve dirty/uncommitted user work. Do not reset, clean, switch branches, or overwrite unrelated changes merely to obtain a clean source tree.

### Mission

Primary focus:
- discover useful new public/authorized data sources, providers, APIs, datasets, registries, archives, tools, and feeds;
- deeply enumerate the real feature surface of each source/tool;
- enrich existing canonical source research with better, newer, or more complete evidence;
- map source capabilities into already-established StarIntel domain boundaries without inventing a new architecture.

### Canonical-node rule

Search the existing research corpus before writing.

- If the question belongs to an existing canonical research node, refine that node.
- Create a new research node only when the question/source/provider is genuinely new and would make the existing node incoherent.
- Do not create duplicate research records merely because a new upstream tool was found.

### Research issue -> durable file invariant

Every GitHub issue that requests, contains, or is created from an ARDR/ADARD research pass MUST have a durable tracked issue-research transaction file under:

`roam/research/ardr-issues/ARDR-ISSUE-<issue-number>-<slug>.org`

If a research issue already exists without that file, backfill the file before doing another pass or advancing the stage.

The issue file must:
- link the exact GitHub issue;
- name every canonical domain research node refined by the issue;
- record the current research question/scope;
- persist substantive findings, sources, contradictions, unresolved questions, and pass history;
- record any downstream design issue/file separately from research approval;
- keep research/design/implementation authority distinct.

GitHub issue bodies/comments are coordination and review evidence. They are not a substitute for the tracked Org research transaction.

### Durable research-file contract

Every research pass MUST persist its substantive findings to tracked Org research files before returning control to the caller. Chat output, task state, issue comments, model memory, scratch notes, logs, and coordinator summaries are not research artifacts.

- Existing canonical question: edit the canonical Org file directly. Preserve its stable `:ID:`, lifecycle metadata, approval metadata, and human approval state. Add the current evidence to the body and add a dated changelog row.
- Genuinely new question: create a new canonical research file with `scripts/save-research.py` and then finish the document to repository standards, including metadata, approval table, changelog, related/index links when applicable, and `* Footnotes and Glossary`.
- Research issue: create/update the matching `roam/research/ardr-issues/ARDR-ISSUE-...org` transaction file in the same pass.
- Never create a second domain file merely to represent another pass over the same coherent research question. Append/refine the canonical node instead.
- A pass is not complete until the canonical file(s) and issue transaction contain the new findings and sources. If files cannot be written, report the research pass as failed/incomplete rather than returning a narrative-only result.
- Before returning, verify the exact paths exist, inspect the resulting diff/content, and run repository validation required by `AGENTS.md` for the changed files.
- The final worker response is only a summary and pointer to durable files. It must name the exact `roam/research/...org` paths written or updated.

### Evidence quality

Use current primary sources first: upstream repositories, official documentation, schemas, API docs, release notes, provider docs, and directly inspectable code. Use broad web search to discover candidate evidence, then verify material claims against authoritative sources where possible.

For each source/tool deeply enumerate:
- inputs and supported identifiers;
- outputs and normalized entities/observations;
- authentication and credential model;
- public/free/paid/local modes;
- pagination, rate limits, concurrency, timeouts, cancellation, retries, and error states;
- data freshness/history coverage;
- provenance and confidence possibilities;
- provider drift/health concerns;
- export/integration surfaces;
- side effects and authorization constraints;
- CAPTCHA/challenge behavior when relevant;
- features StarIntel should reuse;
- missing StarLang/runtime primitives needed to express an already-approved architecture.

### Hard boundaries

- Never promote research to design or architecture unless the active ARDR policy explicitly allows design transition for that exact issue/scope.
- Never mark implementation approved.
- Never implement code from this worker.
- Do not invent actor-per-provider architecture. Prefer coherent domain-server capability families already established by approved design.
- When a design question appears outside an authorized direct-to-design scope, record it in the canonical research file as a human-review question or issue; stop before design promotion.
