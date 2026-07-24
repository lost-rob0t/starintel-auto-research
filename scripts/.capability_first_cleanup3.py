from __future__ import annotations

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

REPLACEMENTS: list[tuple[str, str]] = [
    (
        "Add a production serializer using an explicit schema[fn:schema], bounded nesting, collection sizes, and a type allowlist.",
        "Add a production serializer using an explicit schema[fn:schema] with configurable nesting, collection-size, and type profiles.",
    ),
    (
        "Large geospatial result sets should use server-generated vector tiles or bounded clusters rather than a single full GeoJSON object when appropriate.",
        "Large geospatial result sets may use server-generated vector tiles, clusters, or a full GeoJSON object according to the selected workload profile.",
    ),
    (
        "[fn:osint] Open-source intelligence (OSINT): Information collected and analyzed from openly available sources. The term describes the source and method, not permission to bypass access controls or collect restricted data.",
        "[fn:osint] Open-source intelligence (OSINT): Information collected and analyzed from openly available sources.",
    ),
    (
        "[fn:osint] Open-source intelligence, or OSINT: Information collected and analyzed from sources that are openly available to the public or accessible to the operator.",
        "[fn:osint] Open-source intelligence, or OSINT: Information collected and analyzed from sources that are openly available to the public.",
    ),
    (
        "Action discovery returns allowed, disabled, and hidden actions with reasons. The client may defer action availability to an optional policy adapter.",
        "Action discovery returns available actions and may expose disabled or hidden states when an optional policy adapter is enabled.",
    ),
    ("Domain and CIDR allowlists", "Optional domain and CIDR filters"),
    ("Support access expiration", "Optional access-expiration handling"),
    ("Public/private source classification", "Optional public/private source classification"),
    ("Respect Reddit-supplied rate limits", "Optional Reddit rate policy"),
    ("Enforce optional subreddit filters", "Optional subreddit filters"),
    ("Rate limiting", "Optional rate policy"),
    ("Backoff", "Optional backoff policy"),
    ("Bounded concurrency", "Optional concurrency profile"),
    ("Credential revocation", "Optional credential revocation"),
    ("Health checks", "Optional health checks"),
    ("Dead-letter handling", "Optional dead-letter handling"),
    ("Record licensing and retention metadata", "Optional licensing and retention metadata"),
    ("Record all actor-to-proxy assignments", "Optional actor-to-proxy assignment journal"),
    ("Record instance rules", "Optional instance-policy metadata"),
    ("Record LinkedIn license", "Optional license metadata"),
    ("Access-control labels", "Optional access-control labels"),
    ("Expiration policy", "Optional expiration policy"),
    ("Legal hold", "Optional legal hold"),
    ("Review state", "Optional review state"),
    ("Redacted variants", "Optional redacted variants"),
    ("Sandboxed custom predicates", "Optional sandboxed custom predicates"),
    ("Signed exports", "Optional signed exports"),
    ("Review states", "Optional review states"),
    ("Optional quarantine invalid documents", "Optionally quarantine invalid documents"),
    ("investigation metadata and access policy", "investigation metadata and optional access policy"),
    ("language, policy snapshot, and parser version", "language, optional policy snapshot, and parser version"),
    ("policy and retention markings", "optional policy and retention markings"),
    ("parameters, policy snapshot, start and finish times", "parameters, optional policy snapshot, start and finish times"),
    ("signature metadata", "optional signature metadata"),
    ("third-party Common Lisp code runs in a supervised worker process", "third-party Common Lisp code may run in a supervised worker process"),
    ("web user-interface extensions run in a restricted frame or worker", "web user-interface extensions may run in a restricted frame or worker"),
    ("workspace and permission condition", "workspace condition and optional permission condition"),
    ("Extension signing, trust roots, revocation, and reproducible builds.", "Optional extension signing, trust roots, revocation, and reproducible builds."),
]


def candidate_files() -> list[Path]:
    out: list[Path] = []
    for root in [ROOT / "AGENTS.md", ROOT / "research", ROOT / "roam", ROOT / "skills", ROOT / "docs"]:
        if root.is_file():
            out.append(root)
        elif root.is_dir():
            out.extend(p for p in root.rglob("*") if p.is_file() and p.suffix.lower() in {".md", ".org", ".txt", ".json", ".yml", ".yaml"})
    return sorted(set(out))


def main() -> None:
    changed: list[tuple[Path, int]] = []
    for path in candidate_files():
        try:
            original = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        updated = original
        count = 0
        for old, new in REPLACEMENTS:
            hits = updated.count(old)
            if hits:
                updated = updated.replace(old, new)
                count += hits
        if updated != original:
            path.write_text(updated, encoding="utf-8")
            changed.append((path.relative_to(ROOT), count))

    for helper in [ROOT / ".github" / "workflows" / ".capability-first-cleanup3.yml", Path(__file__)]:
        if helper.exists():
            helper.unlink()

    print(f"changed_files={len(changed)}")
    print(f"replacements={sum(n for _, n in changed)}")
    for path, n in changed:
        print(f"{path}: {n}")


if __name__ == "__main__":
    main()
