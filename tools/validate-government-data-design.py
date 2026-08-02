#!/usr/bin/env python3
"""Validate government-data contracts, fixtures, and generated jurisdiction files offline."""

from __future__ import annotations

import filecmp
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
FIXTURE_DIR = ROOT / "fixtures" / "government-data"
TODO_DIR = ROOT / "roam" / "todos" / "government-data"
GENERATOR = ROOT / "tools" / "generate-government-jurisdiction-todos.py"
CLARIFICATION = (
    ROOT
    / "roam"
    / "design"
    / "auto-research"
    / "STAR-RESEARCH-PIPELINE-004A-government-data-delivery-identity-clarification.org"
)

EXPECTED_ROUTES = (
    "identity",
    "open-data",
    "gis",
    "law",
    "meetings",
    "finance",
    "procurement",
    "property",
    "courts",
    "elections",
    "public-safety",
    "permits",
    "public-records",
    "feeds",
    "archives",
    "operational-metadata",
)

REQUIRED_FRANKLIN_CASES = {
    "unit-create",
    "unit-cas-conflict",
    "component-supersession",
    "subject-owner-self-review",
    "review-cas-conflict",
    "artifact-and-intent-atomic-commit",
    "crash-before-retrieval-event",
    "crash-before-normalization-release",
    "duplicate-delivery-ack",
    "stale-fence-delivery",
    "orphan-artifact-recovery",
    "checkpoint-pending-delivery",
    "success-with-pending-delivery",
    "canonical-basis-equivalence",
    "canonical-basis-mismatch",
    "gate-expiry-without-write",
    "review-invalidation-after-gate",
    "applicability-supersession-after-gate",
    "identity-supersession-after-gate",
    "operational-metadata-derived",
}

STATE_RE = re.compile(r"^\* TODO \[([A-Z]{2})/(\d{2})\] .+ state source catalog ")
COUNTY_RE = re.compile(r"^\*\*\* TODO \[(\d{5})\] (.+?) :([A-Z]{2}):([a-z_]+):$")


def load_json(path: Path) -> dict:
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def validate_routes() -> None:
    path = FIXTURE_DIR / "ohio-route-applicability-v1.0.0.json"
    data = load_json(path)
    routes = data.get("routes", [])
    if len(routes) != 16:
        raise ValueError(f"{path}: expected 16 routes, found {len(routes)}")

    orders = [route.get("order") for route in routes]
    names = [route.get("route") for route in routes]
    if orders != list(range(1, 17)):
        raise ValueError(f"{path}: route order must be exactly 1..16")
    if tuple(names) != EXPECTED_ROUTES:
        raise ValueError(f"{path}: route names/order do not match the canonical contract")
    if len(set(names)) != len(names):
        raise ValueError(f"{path}: duplicate route names")

    allowed = set(data.get("allowed_terminal_states", []))
    if not {"verified-complete", "verified-partial", "not-applicable"} <= allowed:
        raise ValueError(f"{path}: required terminal states are missing")

    for route in routes:
        subfamilies = route.get("subfamilies")
        if not isinstance(subfamilies, list) or not subfamilies:
            raise ValueError(f"{path}: route {route['route']} has no subfamily rules")
        ids = [subfamily.get("id") for subfamily in subfamilies]
        if any(not value for value in ids) or len(ids) != len(set(ids)):
            raise ValueError(f"{path}: route {route['route']} has invalid subfamily IDs")
        for subfamily in subfamilies:
            if subfamily.get("requirement") not in {"required", "conditional", "optional"}:
                raise ValueError(
                    f"{path}: {route['route']}/{subfamily.get('id')} has invalid requirement"
                )

    operational = routes[-1]
    expected = {
        "derived": True,
        "emits_jobs": False,
        "assessment_kind": "derived-gate-assertion",
    }
    for key, value in expected.items():
        if operational.get(key) != value:
            raise ValueError(f"{path}: operational-metadata must set {key}={value!r}")


def validate_franklin_fixtures() -> None:
    path = FIXTURE_DIR / "franklin-gate-and-delivery-v1.0.0.json"
    data = load_json(path)
    cases = data.get("cases", [])
    ids = [case.get("id") for case in cases]
    if len(ids) != len(set(ids)):
        raise ValueError(f"{path}: duplicate fixture case IDs")
    missing = REQUIRED_FRANKLIN_CASES - set(ids)
    if missing:
        raise ValueError(f"{path}: missing required cases: {sorted(missing)}")
    for case in cases:
        if not case.get("operation") or not case.get("expected"):
            raise ValueError(f"{path}: incomplete case {case.get('id')}")


def validate_clarification() -> None:
    text = CLARIFICATION.read_text(encoding="utf-8")
    required_tokens = (
        "government-unit-revision",
        "government-component-revision",
        "route-applicability-contract-revision",
        "government-data-evidence-delivery-intent",
        "evidence-delivery-intent-ids",
        "pending-delivery-step-keys",
        "derived-gate-assertion",
        "Migration never fabricates an acknowledgement",
    )
    missing = [token for token in required_tokens if token not in text]
    if missing:
        raise ValueError(f"{CLARIFICATION}: missing normative tokens: {missing}")


def build_local_roster(destination: Path) -> tuple[int, int]:
    rows: list[str] = []
    states: set[str] = set()
    geoids: set[str] = set()
    current_state: str | None = None

    for shard in sorted(TODO_DIR.glob("STAR-GOVDATA-TODO-???-jurisdictions.org")):
        for line in shard.read_text(encoding="utf-8").splitlines():
            state_match = STATE_RE.match(line)
            if state_match:
                current_state = state_match.group(1)
                states.add(current_state)
                continue
            county_match = COUNTY_RE.match(line)
            if not county_match:
                continue
            geoid, name, tag_state, _kind = county_match.groups()
            if current_state is None or tag_state != current_state:
                raise ValueError(f"{shard}: county {geoid} is outside its state block")
            if geoid in geoids:
                raise ValueError(f"{shard}: duplicate GEOID {geoid}")
            geoids.add(geoid)
            rows.append(f"{current_state}|{geoid}|{name}")

    if len(states) != 52:
        raise ValueError(f"local roster: expected 52 state groups, found {len(states)}")
    if len(rows) != 3_222:
        raise ValueError(f"local roster: expected 3222 rows, found {len(rows)}")

    destination.write_text("\n".join(rows) + "\n", encoding="utf-8")
    return len(states), len(rows)


def compare_generated(expected: Path, actual: Path) -> None:
    expected_files = sorted(path.name for path in expected.glob("STAR-GOVDATA-TODO-*.org"))
    actual_files = sorted(path.name for path in actual.glob("STAR-GOVDATA-TODO-*.org"))
    if expected_files != actual_files:
        raise ValueError("generated jurisdiction file set differs from the checked-in set")

    mismatches = [
        name
        for name in expected_files
        if not filecmp.cmp(expected / name, actual / name, shallow=False)
    ]
    if mismatches:
        raise ValueError(f"generator reproduction mismatch: {mismatches}")


def validate_generator_reproduction() -> None:
    with tempfile.TemporaryDirectory(prefix="starintel-govdata-") as temporary:
        temp = Path(temporary)
        roster = temp / "jurisdictions.txt"
        output = temp / "generated"
        build_local_roster(roster)
        completed = subprocess.run(
            [
                sys.executable,
                str(GENERATOR),
                "--input",
                str(roster),
                "--output-dir",
                str(output),
            ],
            cwd=ROOT,
            check=False,
            text=True,
            capture_output=True,
        )
        if completed.returncode != 0:
            raise ValueError(
                "generator failed:\n"
                f"stdout:\n{completed.stdout}\n"
                f"stderr:\n{completed.stderr}"
            )
        compare_generated(TODO_DIR, output)


def main() -> int:
    try:
        validate_routes()
        validate_franklin_fixtures()
        validate_clarification()
        validate_generator_reproduction()
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"government-data validation failed: {error}", file=sys.stderr)
        return 1
    print("government-data design, fixtures, and generator reproduction validated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
