from __future__ import annotations

from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]

EXACT: list[tuple[str, str]] = [
    (
        "supporting multi-source intelligence (OSINT)[fn:osint]",
        "supporting multi-source intelligence, including open-source intelligence (OSINT)[fn:osint]",
    ),
    ("activity, run, and activity history", "activity and run history"),
    ("Run one local typed action against an target.", "Run one local typed action against a target."),
    ("Granular optional permissions and activity viewer.", "Optional granular permissions and activity viewer."),
    (
        "required capabilities[fn:capability] and permissions",
        "declared capabilities[fn:capability] and optional permission requirements",
    ),
    (
        "The user interface must show why a resource or action is hidden, disabled, redacted, or export-blocked without leaking protected values.",
        "When policy filtering is enabled, the user interface may explain why a resource or action is hidden, disabled, redacted, or export-blocked.",
    ),
    (
        "The optional activity journal records searches, object reads where required, action invocations, query compilation, automated and manual mutations, resolution operations, sharing, exports, permission changes, and administrative overrides.",
        "An optional activity journal may record searches, object reads, action invocations, query compilation, automated and manual mutations, resolution operations, sharing, exports, policy changes, and operator overrides.",
    ),
    (
        "external tools run through bounded actors with explicit arguments and scope;",
        "external tools run through actors with declared arguments and execution configuration;",
    ),
    (
        "Extension results use the same direct action-run, evidence, claim, persistence, provenance, rollback, and audit protocols as built-in actions.",
        "Extension results use the same direct action-run, evidence, claim, persistence, and provenance protocols as built-in actions; deployments may add rollback or activity logging.",
    ),
    (
        "Sensitive identifiers or private query contents must not be serialized into shareable links unless configured otherwise. The service may issue opaque share tokens under explicit policy.",
        "Deployments may omit sensitive identifiers or private query contents from shareable links and may issue opaque share tokens.",
    ),
    (
        "The graph displays a projection, never the entire global graph. It supports:",
        "The graph supports requested projections and full-graph views when the selected storage and renderer can provide them. It supports:",
    ),
    ("compile text into a bounded Star-Lang or query intermediate representation", "compile text into a typed Star-Lang or query intermediate representation"),
    ("Investigation workspace: A bounded project", "Investigation workspace: A project"),
    ("Star-Lang: The bounded declarative language", "Star-Lang: The declarative language"),
    ("Projection: A bounded result", "Projection: A result"),
    ("bounded projection configuration", "projection configuration"),
    ("one giant GeoJSON object", "a single full GeoJSON object when appropriate"),
    ("Enforce collection boundaries", "Optional collection-boundary policy"),
    ("Respect Discord-supplied rate limits", "Optional Discord rate policy"),
    ("Per-chat collection boundaries", "Optional per-chat collection policy"),
    ("Credential isolation", "Optional credential isolation"),
    ("Session revocation", "Optional session revocation"),
    ("Depth limits", "Optional depth policy"),
    ("Rate limits", "Optional rate policy"),
    ("Robots and policy metadata", "Optional robots and source-policy metadata"),
    ("Authentication isolation", "Optional authentication isolation"),
    ("Download quarantine", "Optional download quarantine"),
    ("Popup and navigation controls", "Optional popup and navigation controls"),
    ("Enforce provider-specific limits", "Optional provider-limit policy"),
    ("Disable expired or revoked proxies", "Optional proxy expiration policy"),
    ("Enforce per-instance rate limits", "Optional per-instance rate policy"),
    ("Support instance-specific retention rules", "Support optional instance-specific retention rules"),
    ("Service and repository scope enforcement", "Optional service and repository scope policy"),
    ("Enforce API scopes", "Optional API-scope policy"),
    ("Enforce retention limits", "Optional retention policy"),
    ("Capability-based permissions", "Optional capability-based permissions"),
    ("Sandboxed execution", "Optional sandboxed execution"),
    ("Signed view packages", "Optional signed view packages"),
    ("Static analysis before installation", "Optional static analysis before installation"),
    ("Content Security Policy", "Optional Content Security Policy"),
    ("HTML sanitization", "Optional HTML sanitization"),
    ("Output escaping", "Optional output escaping"),
    ("Emergency disable controls", "Optional emergency disable controls"),
    ("Safe fallback renderer", "Optional fallback renderer"),
    ("Malware scanning", "Optional malware scanning"),
    ("Quarantine", "Optional quarantine"),
    ("Encryption at rest", "Optional encryption at rest"),
    ("Per-file access control", "Optional per-file access control"),
    ("Retention policy", "Optional retention policy"),
    ("Deletion policy", "Optional deletion policy"),
    ("Legal holds", "Optional legal holds"),
    ("Evidence-preservation flags", "Optional evidence-preservation flags"),
    ("Chain-of-custody records", "Optional chain-of-custody records"),
    ("Chain of custody", "Optional chain of custody"),
    ("Preserve government identifiers only in restricted fields", "Preserve government identifiers"),
    ("Quarantine invalid documents without deleting them", "Optionally quarantine invalid documents without deleting them"),
    ("Export redacted variants", "Optional redacted exports"),
    ("Cost and quota estimates are visible before execution.", "Deployments may expose cost and quota estimates before execution."),
    ("Actual cost, retries, failures, and cache hits are recorded afterward.", "Deployments may record cost, retries, failures, and cache hits afterward."),
    ("Parallel and fan-out steps have explicit concurrency bounds.", "Parallel and fan-out steps may use an optional concurrency policy."),
    ("Make minimal, reviewable changes.", "Make coherent, reviewable changes at the scope required by the design."),
    (
        "Apply the `mission-alignment` procedure to the active design, preserve project boundaries and provenance, and make the smallest validated change.",
        "Apply the `mission-alignment` procedure to the active design, preserve project boundaries and provenance, and make the strongest validated change consistent with the user's direction.",
    ),
]

REGEX: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"^(\s*[-*]+\s+)Enforce collection boundaries$", re.MULTILINE), r"\1Optional collection-boundary policy"),
    (re.compile(r"^(\s*[-*]+\s+)Enforce API scopes$", re.MULTILINE), r"\1Optional API-scope policy"),
    (re.compile(r"^(\s*[-*]+\s+)Enforce retention limits$", re.MULTILINE), r"\1Optional retention policy"),
    (re.compile(r"^(\s*[-*]+\s+)Enforce per-instance rate limits$", re.MULTILINE), r"\1Optional per-instance rate policy"),
    (re.compile(r"^(\s*[-*]+\s+)Enforce provider-specific limits$", re.MULTILINE), r"\1Optional provider-limit policy"),
    (re.compile(r"^(\s*[-*]+\s+)Rate limits$", re.MULTILINE), r"\1Optional rate policy"),
    (re.compile(r"^(\s*[-*]+\s+)Retention policy$", re.MULTILINE), r"\1Optional retention policy"),
    (re.compile(r"^(\s*[-*]+\s+)Deletion policy$", re.MULTILINE), r"\1Optional deletion policy"),
    (re.compile(r"^(\s*[-*]+\s+)Legal hold$", re.MULTILINE), r"\1Optional legal hold"),
    (re.compile(r"^(\s*[-*]+\s+)Chain of custody$", re.MULTILINE), r"\1Optional chain of custody"),
    (re.compile(r"\bbounded actors\b"), "actors"),
    (re.compile(r"\bbounded Star-Lang\b"), "typed Star-Lang"),
    (re.compile(r"\bbounded result sets\b"), "result sets"),
]


def files() -> list[Path]:
    result: list[Path] = []
    for root in [ROOT / "AGENTS.md", ROOT / "research", ROOT / "roam", ROOT / "skills", ROOT / "docs"]:
        if root.is_file():
            result.append(root)
        elif root.is_dir():
            result.extend(p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in {".md", ".org", ".txt", ".json", ".yml", ".yaml"})
    return sorted(set(result))


def main() -> None:
    changed: list[tuple[Path, int]] = []
    for path in files():
        try:
            old = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        new = old
        count = 0
        for source, replacement in EXACT:
            hits = new.count(source)
            if hits:
                new = new.replace(source, replacement)
                count += hits
        for pattern, replacement in REGEX:
            new, hits = pattern.subn(replacement, new)
            count += hits
        if new != old:
            path.write_text(new, encoding="utf-8")
            changed.append((path.relative_to(ROOT), count))

    for helper in [
        ROOT / ".github" / "workflows" / ".capability-first-cleanup2.yml",
        Path(__file__),
    ]:
        if helper.exists():
            helper.unlink()

    print(f"changed_files={len(changed)}")
    print(f"replacements={sum(count for _, count in changed)}")
    for path, count in changed:
        print(f"{path}: {count}")


if __name__ == "__main__":
    main()
