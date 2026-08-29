---
name: "save-research"
description: "Persist StarIntel research in the authoritative local Auto-Research checkout."
version: "1.1.0"
author: "lost-rob0t"
category: "workflow"
tags: ["starintel", "workflow", "save-research", "source-of-truth", "ardr"]
---

# Save Research

## Objective

Persist every substantive research pass to tracked Org files in the authoritative StarIntel Auto-Research checkout. Issue prose, chat output, scratch state, and remote GitHub state are never substitutes for the local research corpus.

## Source-of-truth checkout gate

The default authoritative checkout is:

```text
~/starintel/starintel-auto-research
```

Expand `~` using the current user's home directory and verify all of the following before any research read/write:

1. `$HOME/starintel/starintel-auto-research` exists as a directory.
2. It is a Git worktree/repository.
3. It contains the repository `AGENTS.md`.
4. The applicable repository instructions are read before editing.

If the default checkout does **not** exist, STOP. Ask the user to provide the correct path to their `starintel-auto-research` checkout.

Do **not**:
- clone a replacement automatically;
- create the missing directory;
- guess another checkout path;
- search the filesystem and silently pick a different clone;
- use the current working directory as a substitute;
- treat GitHub/Forgejo/remote contents as the source of truth;
- reset, clean, stash, switch, or overwrite dirty user work merely to obtain a clean tree.

If the user supplies an alternate checkout path, use that path for the task and read its applicable `AGENTS.md`. Do not permanently change the default path unless the user explicitly requests that separately.

## Research issue invariant

Every GitHub issue that requests, contains, or is created from an ARDR/ADARD research pass must have a durable issue-research transaction file:

```text
roam/research/ardr-issues/ARDR-ISSUE-<issue-number>-<slug>.org
```

The transaction file is required even when the issue also refines an existing domain research node. In that case, the transaction links the canonical domain node and records each pass without duplicating the domain research question.

Creating a research issue without its Org transaction is incomplete. Finding an older issue without a transaction requires backfilling the file before more research or stage advancement.

## Preconditions

- Enter the authoritative checkout resolved by the source-of-truth gate.
- Read the applicable `AGENTS.md` files.
- Inspect `git status --short`, current branch, and remotes before writing.
- Preserve every unrelated local change.
- Search the existing research corpus before creating a new domain research node.
- Do not bulk-load `roam/` when a bounded search is sufficient.

## Procedure

1. Resolve the authoritative checkout; stop and ask the user for a path if the default is absent.
2. Identify the GitHub issue, if any, and locate/create its `ARDR-ISSUE-...org` transaction.
3. Search canonical research/indexes for an existing coherent research node.
4. Refine the existing canonical node when the question belongs there; create a new node only for a genuinely new coherent question.
5. Persist findings, sources, contradictions, unresolved questions, and a dated changelog entry in tracked Org files.
6. Keep approval state separate from lifecycle/design readiness. Never infer implementation approval.
7. Update the applicable research/index links in the same change.
8. Run the repository's required narrow and canonical validations from `AGENTS.md`.
9. Report the exact files changed and observed validation results.

## Exit Criteria

- The authoritative local checkout was used.
- Every issue-backed research pass has a tracked `ARDR-ISSUE-...org` transaction.
- All substantive findings from the pass exist in tracked Org files.
- Canonical domain research was refined rather than duplicated when appropriate.
- Approval/changelog/metadata requirements are satisfied.
- Tests/checks are reported with exact observed results.
- No unrelated files, secrets, unsupported claims, hidden source-of-truth substitutions, or implementation approvals were introduced.
