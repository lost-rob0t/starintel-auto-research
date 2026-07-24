from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

EXACT_REPLACEMENTS: list[tuple[str, str]] = [
    (
        "Product line: **the world's most dangerous search engine**—dangerous because it can preserve, normalize, connect, and search fragmented public or authorized data while retaining evidence and provenance.",
        "Product line: **the world's most dangerous search engine**—dangerous because it can preserve, normalize, connect, search, and analyze fragmented data across public, private, commercial, supplied, acquired, platform, sensor, and archival sources while supporting evidence and provenance.",
    ),
    (
        "Build Starintel as a local-first, professional intelligence platform: a document-driven, actor-based search and analysis system that can run at home and scale into a hosted service.",
        "Build Starintel as a local-first, professional intelligence platform: a document-driven, actor-based collection, search, correlation, automation, and analysis system that can run at home and scale into a hosted service. Its purpose is to give ordinary operators the investigative reach needed to expose lobbying, procurement, institutional influence, surveillance deployments, ownership networks, coordinated activity, and other concentrations of power.",
    ),
    ("public or otherwise authorized open-source intelligence", "multi-source intelligence"),
    ("public or otherwise authorized data", "heterogeneous source data"),
    ("public or authorized data", "heterogeneous source data"),
    ("public and authorized data collection", "multi-source data collection"),
    ("public or authorized", "configured source access"),
    ("otherwise lawfully accessible to the operator", "accessible to the operator"),
    ("legally accessible public sources", "openly available sources"),
    ("authorized Nmap run", "Nmap run"),
    ("authorized datasets", "configured datasets"),
    ("authorized target", "target"),
    ("where authorized", "when enabled"),
    ("public accounts", "accounts"),
    ("public account candidates", "account candidates"),
    ("public-source collection", "source collection"),
    ("Record approved accounts", "Record configured accounts"),
    ("Record approved guilds and channels", "Record configured guilds and channels"),
    ("Approved chat identifiers", "Configured chat identifiers"),
    ("approved chat identifiers", "configured chat identifiers"),
    ("approved domains", "configured domains"),
    ("approved fixtures", "test fixtures"),
    ("Request human or policy approval", "Resolve execution configuration"),
    ("Approved-domain enforcement", "Optional target-domain filtering"),
    ("Approved-action policies", "Optional action policy"),
    ("approved project", "assigned operation"),
    ("approved organizations", "configured organizations"),
    ("account-owner consent", "account acquisition context"),
    ("Reject out-of-scope profile or relationship collection", "Apply optional profile and relationship filters"),
    ("sites whose operators have approved collection", "sites selected by the operator"),
    ("supplied or approved by the operating organization, customer, platform, or collection provider", "supplied by the operator, customer, platform, or collection provider"),
    ("Bind every proxy to an approved project", "Optionally bind a proxy to an operation"),
    ("Human approvals", "Optional review decisions"),
    ("Human confirmation", "Optional analyst confirmation"),
    ("Administrative approval", "Optional installation policy"),
    ("approved annotations", "selected annotations"),
    ("Public-safe variants", "Distribution variants"),
    ("Audit trail for every operation", "Optional operation journal"),
    ("Produce complete audit logs", "Support optional execution logs"),
    ("Complete interaction logs", "Optional interaction logs"),
    ("Complete audit trail", "Optional execution history"),
    ("Audit every execution", "Support optional execution logging"),
    ("audit and telemetry emission", "optional telemetry emission"),
    ("permissions and audit viewer", "optional permissions and activity viewer"),
    ("append-only audit journal", "optional activity journal"),
    ("The append-only audit journal records", "An optional activity journal may record"),
    ("an append-only audit journal", "an optional activity journal"),
    ("audit journal", "activity journal"),
    ("audit history", "activity history"),
    ("audit logs", "execution logs"),
    ("audit trail", "execution history"),
    ("Require structured LLM output", "Support structured LLM output"),
    ("Require deterministic validation", "Support deterministic validation"),
    ("Require schema validation", "Support schema validation"),
    ("Require target.data", "Read target.data"),
    ("Human-review queues", "Optional analyst queues"),
    ("Human review state", "Optional analyst review state"),
    ("human review", "optional analyst review"),
    ("Human-review checkpoints", "Optional analyst checkpoints"),
    ("human-review checkpoints", "optional analyst checkpoints"),
    ("mandatory review gates", "mandatory review gates"),
    ("public links by default", "shareable links unless configured otherwise"),
    ("must not be serialized into public links by default", "may be omitted from shareable links by deployment policy"),
    ("never determines authorization only from a menu predicate", "may defer action availability to an optional policy adapter"),
    ("under configured policy and resource checks without requiring a separate human confirmation step", "directly, while allowing deployments to add optional policy and resource adapters"),
    ("Permissions may apply to", "Optional access rules may apply to"),
    ("Derived material inherits policy according to declared propagation rules.", "Deployments that enable access rules may define propagation for derived material."),
    ("Default execution boundaries are:", "Optional isolation profiles include:"),
    ("no extension receives ambient database, filesystem, credential, network, or shell access.", "deployments may restrict ambient database, filesystem, credential, network, or shell access."),
    ("policy-server=: capability, permission, marking, retention, and export decisions", "policy-adapter=: optional capability, permission, marking, retention, and export decisions"),
    ("policy-server", "policy-adapter"),
    ("Public and authorized data collection is the default operating boundary.", "Source classes and operating boundaries are selected by the operator and deployment."),
    ("live actor or sensor status where authorized", "live actor or sensor status"),
]

REGEX_REPLACEMENTS: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"^(\*+ TODO )Required controls$", re.MULTILINE), r"\1Optional deployment modules"),
    (re.compile(r"^(\*+ TODO )Access controls$", re.MULTILINE), r"\1Optional access module"),
    (re.compile(r"^(\*+ TODO )Scope controls$", re.MULTILINE), r"\1Optional scope module"),
    (re.compile(r"^(\*+ TODO )Restrictions$", re.MULTILINE), r"\1Optional deployment restrictions"),
    (re.compile(r"^(\*+ )Collaboration, Permissions, and Governance$", re.MULTILINE), r"\1Collaboration and Optional Governance"),
    (re.compile(r"^(\*+ )Extension System and Trust Boundaries$", re.MULTILINE), r"\1Extension System and Optional Isolation"),
    (re.compile(r"^(\*+ TODO )Required Sento extension dependency$", re.MULTILINE), r"\1Sento extension dependency"),
    (re.compile(r"\bDomain allowlists\b"), "Optional domain filters"),
    (re.compile(r"\bPath allowlists\b"), "Optional path filters"),
    (re.compile(r"\bsubreddit allowlists\b", re.IGNORECASE), "optional subreddit filters"),
    (re.compile(r"\bBoard allowlists\b"), "Optional board filters"),
    (re.compile(r"\bDependency allowlists\b"), "Optional dependency policy"),
    (re.compile(r"\bPer-view field allowlists\b"), "Optional per-view field filters"),
    (re.compile(r"\bPer-view dataset allowlists\b"), "Optional per-view dataset filters"),
    (re.compile(r"\bOut-of-scope rejection\b"), "Optional target filtering"),
    (re.compile(r"\bPer-tool safety policy\b"), "Optional per-tool policy"),
    (re.compile(r"\bTarget locks\b"), "Optional target locks"),
    (re.compile(r"\bRate-limit enforcement\b"), "Optional rate-limit policy"),
    (re.compile(r"\bCollection-rate limits\b"), "Optional collection-rate policy"),
    (re.compile(r"\bRequest-rate limits\b"), "Optional request-rate policy"),
    (re.compile(r"\bRequest budgets\b"), "Optional request budgets"),
    (re.compile(r"\bExecution timeouts\b"), "Optional execution timeouts"),
    (re.compile(r"\bBrowser resource limits\b"), "Optional browser resource limits"),
    (re.compile(r"\bCPU limits\b"), "Optional CPU limits"),
    (re.compile(r"\bMemory limits\b"), "Optional memory limits"),
    (re.compile(r"\bExecution-time limits\b"), "Optional execution-time limits"),
    (re.compile(r"\bOutput-size limits\b"), "Optional output-size limits"),
    (re.compile(r"\bDownload limits\b"), "Optional download limits"),
    (re.compile(r"\bBandwidth limits\b"), "Optional bandwidth limits"),
    (re.compile(r"\bGraph traversal limits\b"), "Optional graph traversal limits"),
    (re.compile(r"\bQuery budgets\b"), "Optional query budgets"),
    (re.compile(r"\bRecursion limits\b"), "Optional recursion limits"),
    (re.compile(r"\bInference-time limits\b"), "Optional inference-time limits"),
    (re.compile(r"\bRead-only data access by default\b"), "Optional read-only mode"),
    (re.compile(r"\bNo network access by default\b"), "Optional network restriction"),
    (re.compile(r"\bNo filesystem access by default\b"), "Optional filesystem restriction"),
    (re.compile(r"\bNo process execution by default\b"), "Optional process-execution restriction"),
    (re.compile(r"\bNo secret access by default\b"), "Optional secret-access restriction"),
    (re.compile(r"\bAutomatic shutdown on scope violation\b"), "Optional shutdown on configured boundary violation"),
    (re.compile(r"\bDisable collection automatically when access expires\b"), "Optional collection shutdown on access expiration"),
    (re.compile(r"\bDisable collection on access revocation\b"), "Optional collection shutdown on access revocation"),
    (re.compile(r"\bPrevent cross-case data leakage\b"), "Optional case-isolation policy"),
    (re.compile(r"\bPrevent automatic cross-case data leakage\b"), "Optional case-isolation policy"),
    (re.compile(r"\bCase-specific access controls\b"), "Optional case-specific access controls"),
    (re.compile(r"\bPermission-aware indexing\b"), "Optional permission-aware indexing"),
    (re.compile(r"\bGranular permissions\b"), "Optional granular permissions"),
    (re.compile(r"\brequired permissions and capabilities\b", re.IGNORECASE), "declared capabilities and optional permission requirements"),
    (re.compile(r"\brequired capabilities and permissions\b", re.IGNORECASE), "declared capabilities and optional permission requirements"),
    (re.compile(r"\brequired capabilities and credentials\b", re.IGNORECASE), "declared capabilities and credentials"),
    (re.compile(r"\bscope, time, concurrency, memory, and monetary limits\b"), "optional scope, time, concurrency, memory, and monetary policies"),
    (re.compile(r"\bconcurrency, rate, time, memory, and monetary limits\b"), "optional concurrency, rate, time, memory, and monetary policies"),
    (re.compile(r"\bexpected fan-out and hard result limit\b"), "expected fan-out and optional result policy"),
    (re.compile(r"\bexplicit node, edge, time, and memory budgets\b"), "configurable node, edge, time, and memory profiles"),
    (re.compile(r"\bmaximum feature budget\b"), "optional feature budget"),
    (re.compile(r"\bprojection budget exceeded\b"), "projection policy exceeded"),
    (re.compile(r"\bbounded deep links\b"), "shareable deep links"),
    (re.compile(r"\bbounded graph projection\b"), "graph projection"),
    (re.compile(r"\bbounded projection\b"), "projection"),
    (re.compile(r"\bbounded graph\b"), "graph"),
    (re.compile(r"\bbounded collection\b"), "collection"),
    (re.compile(r"\bbounded inference\b"), "inference"),
    (re.compile(r"\bbounded scope\b"), "configured scope"),
]

CAPABILITY_SECTION = """

## Capability-First Principle

Starintel is an anti-technofeudalist intelligence tool. Its core must maximize collection breadth, source interoperability, entity resolution, relationship discovery, graph analysis, automation, replay, search, and operator-controlled execution. It must not be reduced to a public-record viewer or preemptively narrowed around the operating assumptions of a future company.

Approval gates, audits, permissions, allowlists, retention rules, rate policies, resource policies, review queues, redaction, and deployment governance are optional modules selected by the operator or product deployment. They are not universal prerequisites, mandatory document fields, or limits on the core capability model.

Research must first identify the strongest technically achievable capability. Deployment policy may wrap that capability later without rewriting or weakening the underlying architecture.
"""


def candidate_files() -> list[Path]:
    files: list[Path] = []
    for item in [ROOT / "AGENTS.md", ROOT / "research", ROOT / "roam", ROOT / "skills", ROOT / "docs"]:
        if item.is_file():
            files.append(item)
        elif item.is_dir():
            files.extend(p for p in item.rglob("*") if p.is_file() and p.suffix.lower() in {".md", ".org", ".txt", ".json", ".yml", ".yaml"})
    return sorted(set(files))


def patch_file(path: Path) -> tuple[bool, int]:
    try:
        original = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return False, 0

    updated = original
    count = 0
    for old, new in EXACT_REPLACEMENTS:
        hits = updated.count(old)
        if hits:
            updated = updated.replace(old, new)
            count += hits

    for pattern, replacement in REGEX_REPLACEMENTS:
        updated, hits = pattern.subn(replacement, updated)
        count += hits

    if path == ROOT / "AGENTS.md" and "## Capability-First Principle" not in updated:
        marker = "\n## Context Order\n"
        if marker not in updated:
            raise RuntimeError("AGENTS.md context marker not found")
        updated = updated.replace(marker, CAPABILITY_SECTION + marker, 1)
        count += 1

    # The public repository must not instruct future agents to reintroduce universal controls.
    if path == ROOT / "AGENTS.md":
        old = "5. Preserve lifecycle, provenance, integrity, access, search, storage, and processing metadata.\n6. Never fabricate sources, confidence, authorization, or evidence."
        new = "5. Keep lifecycle, provenance, integrity, access, audit, retention, and processing metadata optional unless the active design explicitly requires them.\n6. Never fabricate sources, confidence, or evidence."
        if old in updated:
            updated = updated.replace(old, new)
            count += 1

    if updated != original:
        path.write_text(updated, encoding="utf-8")
        return True, count
    return False, 0


def main() -> None:
    changed: list[tuple[Path, int]] = []
    for path in candidate_files():
        did_change, replacements = patch_file(path)
        if did_change:
            changed.append((path.relative_to(ROOT), replacements))

    # Remove the one-shot machinery so the PR contains only the requested repository cleanup.
    workflow = ROOT / ".github" / "workflows" / ".capability-first-cleanup.yml"
    script = Path(__file__)
    if workflow.exists():
        workflow.unlink()
    if script.exists():
        script.unlink()

    print(f"changed_files={len(changed)}")
    print(f"replacements={sum(count for _, count in changed)}")
    for path, replacements in changed:
        print(f"{path}: {replacements}")


if __name__ == "__main__":
    main()
