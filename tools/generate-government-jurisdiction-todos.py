#!/usr/bin/env python3
"""Generate the StarIntel Org TODO catalog for every U.S. state and county-equivalent."""

from __future__ import annotations

import argparse
import csv
import io
import re
import sys
import urllib.error
import urllib.request
import zipfile
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

SOURCE_URL = (
    "https://www2.census.gov/geo/docs/maps-data/data/gazetteer/"
    "2025_Gazetteer/2025_Gaz_counties_national.zip"
)
SOURCE_MEMBER = "2025_Gaz_counties_national.txt"
EXPECTED_ROWS = 3_222
EXPECTED_GROUPS = 52
DEFAULT_OUTPUT = Path("roam/todos/government-data")
MASTER_NAME = "STAR-GOVDATA-TODO-000-jurisdiction-source-catalog.org"

STATE_NAMES = {
    "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas",
    "CA": "California", "CO": "Colorado", "CT": "Connecticut",
    "DE": "Delaware", "DC": "District of Columbia", "FL": "Florida",
    "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho", "IL": "Illinois",
    "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky",
    "LA": "Louisiana", "ME": "Maine", "MD": "Maryland",
    "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota",
    "MS": "Mississippi", "MO": "Missouri", "MT": "Montana",
    "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire",
    "NJ": "New Jersey", "NM": "New Mexico", "NY": "New York",
    "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio",
    "OK": "Oklahoma", "OR": "Oregon", "PA": "Pennsylvania",
    "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota",
    "TN": "Tennessee", "TX": "Texas", "UT": "Utah", "VT": "Vermont",
    "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
    "WI": "Wisconsin", "WY": "Wyoming", "PR": "Puerto Rico",
}

SHARD_GROUPS = (
    ("AL", "AK", "AZ", "AR"),
    ("CA", "CO", "CT", "DE", "DC", "FL"),
    ("GA", "HI", "ID"),
    ("IL", "IN"),
    ("IA", "KS"),
    ("KY", "LA", "ME", "MD", "MA"),
    ("MI", "MN"),
    ("MS", "MO"),
    ("MT", "NE", "NV", "NH", "NJ", "NM"),
    ("NY", "NC", "ND"),
    ("OH", "OK", "OR"),
    ("PA", "RI", "SC", "SD"),
    ("TN",),
    ("TX",),
    ("UT", "VT", "VA", "WA"),
    ("WV", "WI", "WY", "PR"),
)

SOURCE_ROUTES = (
    "Official identity, domains, aliases, components, delegated hosting, and service-provider topology.",
    "Open-data catalogs/platforms/exports and reviewed absence.",
    "GIS, parcels, ArcGIS/OGC, downloads, viewers, and provider mapping.",
    "Charter, code, ordinances, resolutions, laws, policies, and version relationships.",
    "Meetings, calendars, agendas, packets, minutes, votes, transcripts, recordings, and archives.",
    "Budgets, financial reports, audits, checkbooks, payroll, debt, grants, revenue, and scope gaps.",
    "Procurement, bids, awards, contracts, purchase orders, attachments, and vendor payments.",
    "Property, assessment, tax, recorder, deed, parcel, and land-record systems/providers.",
    "Court/clerk topology, dockets, indexes, documents, restrictions, and linked local-court assessments.",
    "Elections, candidates, campaign finance, precincts, result states, and voter-information products.",
    "Sheriff, jail, incident, dispatch, inspection, enforcement, and lawfully public safety systems.",
    "Building, zoning, planning, development, health, environmental, licensing, and code providers/systems.",
    "Public-records method, policy, retention, contacts, fees, and escalation instructions.",
    "Sitemaps, feeds, alerts, newsletters, APIs, exports, and change feeds or reviewed absence.",
    "Archives, retired domains, repositories, migrations, predecessor/successor links, and date bounds.",
    "Cross-cutting operational metadata for every source, decision, review, gap, artifact, and acquisition path.",
)

OUTPUT_FIELDS = (
    "jurisdiction-completion gate and gate-review revision IDs",
    "source-contract ID/version and source-contract review revision",
    "applicability-contract ID/version/review and policy snapshot/review",
    "gate basis schema, hash algorithm, basis-as-of, basis hash, freshness deadline, and valid-through",
    "route-assessment and route-review revision IDs",
    "subfamily, profile, deployment, search-plan, gap, and subject-review revision IDs",
    "authority/status evidence, component, data family, and service geography",
    "platform/vendor/tenant, adapter version, manifest/runtime hashes",
    "locator, discovery, predecessor/successor, and archive evidence",
    "access, credential, lease fence, legal, privacy, and browser constraints",
    "temporal/jurisdictional completeness scope",
    "artifact, retrieval-event, evidence, and content hashes",
    "cursor/checkpoint/reconciliation method",
    "negative/access/partial/retired/OCR/manual-review state",
    "freshness and reassessment deadline",
    "reviewer identity/generation and independence-policy result",
)


@dataclass(frozen=True, slots=True)
class Jurisdiction:
    usps: str
    geoid: str
    name: str

    @property
    def state_fips(self) -> str:
        return self.geoid[:2]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--input",
        type=Path,
        help="Optional local Census ZIP/TXT or compact USPS|GEOID|NAME file.",
    )
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--source-url", default=SOURCE_URL)
    return parser.parse_args()


def fetch_source(url: str) -> bytes:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": "starintel-auto-research/1"},
    )
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def read_source(path: Path | None, url: str) -> str:
    data = path.read_bytes() if path else fetch_source(url)
    if (path and path.suffix.lower() == ".zip") or data.startswith(b"PK\x03\x04"):
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            member = SOURCE_MEMBER if SOURCE_MEMBER in archive.namelist() else archive.namelist()[0]
            data = archive.read(member)
    for encoding in ("utf-8-sig", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            continue
    raise ValueError("Unable to decode Census source")


def parse_rows(text: str) -> list[Jurisdiction]:
    lines = [line.strip() for line in text.replace("\r", "").splitlines() if line.strip()]
    if not lines:
        raise ValueError("Census source is empty")
    has_header = lines[0].split("|")[:2] == ["USPS", "GEOID"]
    rows: list[Jurisdiction] = []
    source_lines = lines[1:] if has_header else lines
    start = 2 if has_header else 1
    for line_number, line in enumerate(source_lines, start=start):
        fields = next(csv.reader([line], delimiter="|"))
        if len(fields) >= 5:
            usps, geoid, name = fields[0], fields[1], fields[4]
        elif len(fields) == 3:
            usps, geoid, name = fields
        else:
            raise ValueError(f"Line {line_number}: expected 3 or at least 5 fields")
        rows.append(Jurisdiction(usps.strip(), geoid.strip(), name.strip()))
    return rows


def validate(rows: Iterable[Jurisdiction]) -> list[Jurisdiction]:
    result = list(rows)
    if len(result) != EXPECTED_ROWS:
        raise ValueError(f"Expected {EXPECTED_ROWS} rows, found {len(result)}")
    geoids = [row.geoid for row in result]
    if len(set(geoids)) != EXPECTED_ROWS:
        raise ValueError("Duplicate county-equivalent GEOIDs")
    for row in result:
        if row.usps not in STATE_NAMES:
            raise ValueError(f"Unknown USPS group: {row.usps}")
        if not re.fullmatch(r"\d{5}", row.geoid):
            raise ValueError(f"Invalid GEOID: {row.geoid}")
        if not row.name:
            raise ValueError(f"Missing name for GEOID {row.geoid}")
    groups = {row.usps for row in result}
    if groups != set(STATE_NAMES):
        raise ValueError("State/territory group set does not match the expected 52 groups")
    flattened = [code for shard in SHARD_GROUPS for code in shard]
    if len(flattened) != EXPECTED_GROUPS or set(flattened) != groups:
        raise ValueError("Shard groups must contain each state/territory exactly once")
    return result


def jurisdiction_type(name: str) -> str:
    suffixes = (
        (" Municipio", "municipio"),
        (" Planning Region", "planning_region"),
        (" Census Area", "census_area"),
        (" City and Borough", "city_and_borough"),
        (" Borough", "borough"),
        (" Parish", "parish"),
        (" District", "district"),
        (" Municipality", "municipality"),
    )
    for suffix, kind in suffixes:
        if name.endswith(suffix):
            return kind
    if name.lower().endswith(" city"):
        return "independent_city"
    return "county"


def group_rows(rows: list[Jurisdiction]) -> dict[str, list[Jurisdiction]]:
    groups: dict[str, list[Jurisdiction]] = defaultdict(list)
    for row in rows:
        groups[row.usps].append(row)
    for state_rows in groups.values():
        state_rows.sort(key=lambda row: row.geoid)
    return groups


def render_state(usps: str, rows: list[Jurisdiction]) -> str:
    state_fips = rows[0].state_fips
    lines = [
        f"* TODO [{usps}/{state_fips}] {STATE_NAMES[usps]} state source catalog :state:{usps}:",
        ":PROPERTIES:",
        f":COUNTY_EQUIVALENTS: {len(rows)}",
        ":CHECKLIST: jurisdiction-source-profile-v1",
        ":END:",
        "- [ ] Verify the identity spine, official domains, statewide portals, shared services, public-records law, retention rules, and access constraints.",
        "- [ ] Review every county or county-equivalent TODO below.",
        "",
        "** County and county-equivalent TODOs",
        "",
    ]
    lines.extend(
        f"*** TODO [{row.geoid}] {row.name} :{usps}:{jurisdiction_type(row.name)}:"
        for row in rows
    )
    return "\n".join(lines).rstrip() + "\n"


def render_shard(
    number: int,
    state_codes: tuple[str, ...],
    groups: dict[str, list[Jurisdiction]],
) -> str:
    first = STATE_NAMES[state_codes[0]]
    last = STATE_NAMES[state_codes[-1]]
    lines = [
        ":PROPERTIES:",
        f":ID:       starintel-government-data-jurisdiction-todos-{number:03d}",
        ":END:",
        f"#+title: STAR-GOVDATA-TODO-{number:03d} Jurisdictions {first} through {last}",
        "#+description: Generated GEOID-keyed TODO shard from the 2025 Census Gazetteer county-equivalent roster.",
        "#+status: ACTIVE",
        "#+filetags: :starintel:todo:government-data:states:counties:generated:",
        "#+todo: TODO RESEARCHING REVIEW BLOCKED | DONE REJECTED",
        "",
        "* Generation Rule",
        "",
        "- Generated by =tools/generate-government-jurisdiction-todos.py=.",
        "- Do not hand-edit generated jurisdiction headings.",
        "- Complete each heading under the contract in =STAR-GOVDATA-TODO-000=.",
        "",
    ]
    header = "\n".join(lines).rstrip() + "\n\n"
    body = "\n\n".join(render_state(code, groups[code]).rstrip() for code in state_codes)
    return header + body + "\n"


def render_master() -> str:
    lines = [
        ":PROPERTIES:",
        ":ID:       starintel-government-data-jurisdiction-todos-000",
        ":END:",
        "#+title: STAR-GOVDATA-TODO-000 State and County Source Catalog",
        "#+description: Generated Org TODO queue for every 2025 Census state group and county or county-equivalent, with stable GEOIDs and a shared source-catalog completion contract.",
        "#+status: ACTIVE",
        "#+filetags: :starintel:todo:government-data:states:counties:catalog:gates:",
        "#+todo: TODO RESEARCHING REVIEW BLOCKED | DONE REJECTED",
        "",
        "| Version | Date       | Description of change                                                    | Did nsaspy approve it |",
        "|---------+------------+--------------------------------------------------------------------------+-----------------------|",
        "| 0.1.0   | 2026-07-28 | Seed state and county-equivalent source-catalog TODO queue                | Pending               |",
        "| 0.2.0   | 2026-07-28 | Require immutable reviewed route decisions before completion             | Pending               |",
        "| 0.3.0   | 2026-07-28 | Require a separately reviewed atomic jurisdiction-completion gate        | Pending               |",
        "| 0.4.0   | 2026-07-28 | Bind reviewed source contract and deterministic gate validity/hash       | Pending               |",
        "",
        "* Related Nodes",
        "",
        "- [[file:../../indexes/auto-research/STAR-RESEARCH-PIPELINE-INDEX-000-adaptive-research.org][STAR-RESEARCH-PIPELINE-INDEX-000 Adaptive Research]]",
        "- [[file:../../research/auto-research/STAR-RESEARCH-003-us-government-data-acquisition-landscape.org][STAR-RESEARCH-003 U.S. Government Data Acquisition Landscape]]",
        "- [[file:../../design/auto-research/STAR-RESEARCH-PIPELINE-003-government-data-acquisition-actors.org][STAR-RESEARCH-PIPELINE-003 Government Data Acquisition Actors]]",
        "- [[file:../../design/auto-research/STAR-RESEARCH-PIPELINE-004-government-data-revision-protocol-amendment.org][STAR-RESEARCH-PIPELINE-004 Government Data Revision Protocol Amendment]]",
        "- [[file:../../design/government-data/STAR-GOVDATA-DESIGN-001-ohio-coverage-program.org][STAR-GOVDATA-DESIGN-001 Ohio Government Data Coverage Program]]",
        "- [[file:../../design/government-data/STAR-GOVDATA-DESIGN-002-ohio-source-profile-contract.org][STAR-GOVDATA-DESIGN-002 Ohio Source Profile Contract]]",
        "- [[file:../../design/government-data/STAR-GOVDATA-DESIGN-003-ohio-adapter-pack.org][STAR-GOVDATA-DESIGN-003 Ohio Adapter Pack]]",
        "",
        "* Source and Generation",
        "",
        "- Source vintage: 2025 Census Gazetteer county and county-equivalent national file.",
        f"- Source locator: ={SOURCE_URL}=.",
        "- Generated state-level queues: 52.",
        "- Generated county/county-equivalent TODOs: 3,222.",
        "- Regenerate with =tools/generate-government-jurisdiction-todos.py=; do not hand-edit generated shards.",
        "- The shard =:CHECKLIST:= value is a stable logical contract key. Exact source/applicability contract and policy versions are pinned by gate revisions.",
        "",
        "* Active State Designs",
        "",
        "** REVIEW Ohio",
        "",
        "Ohio is the first state design. Generated Ohio/county headings remain =TODO=. Design work, candidates, profiles, assessments, or unreviewed gates do not count as completion.",
        "",
        "* Completion Contract",
        "",
        "A jurisdiction reaches =DONE= only when the Coverage Gate Authority has committed one =:jurisdiction-completion= gate revision with =status :passed= and the Independent Review Authority has committed a separate =:reviewed= review decision for that exact gate revision.",
        "",
        "The gate binds atomically:",
        "",
        "- one independently reviewed =star.govdata.source-profile= source-contract version",
        "- one independently reviewed applicability-contract version",
        "- one reviewed policy snapshot and reviewed adapter manifest/runtime sets",
        "- exact route-assessment revisions for all sixteen routes",
        "- exact review-decision revisions for every route assessment and required subject",
        "- exact subfamily, profile, deployment, search-plan, and gap revisions",
        "- immutable evidence, retrieval events, and artifacts",
        "- canonical basis schema, hash algorithm, basis time/hash, freshness deadline, and valid-through",
        "",
        "The gate decider and reviewer satisfy independence policy.",
        "",
        "Candidate, ambiguous, unassessed, stale, mutable, unresolved manual review, missing applicability, blocked/expired, hash mismatch, invalidated review, source-contract mismatch, or current time after =valid-through= blocks =DONE=.",
        "",
        "Changes never mutate a passed gate. They may make it non-current and require new subject/review/gate revisions.",
        "",
        "Operational metadata is cross-cutting and requires platform, access, lease, cursor, refresh, scope, provenance, truncation, and reassessment fields across all bound subjects.",
        "",
        "* Required Source Routes",
        "",
    ]
    lines.extend(f"{number}. {route}" for number, route in enumerate(SOURCE_ROUTES, 1))
    lines.extend(["", "* Required Output Bindings", ""])
    lines.extend(f"- {field}" for field in OUTPUT_FIELDS)
    lines.extend(["", "* Generated Jurisdiction Shards", ""])
    for number, codes in enumerate(SHARD_GROUPS, 1):
        first = STATE_NAMES[codes[0]]
        last = STATE_NAMES[codes[-1]]
        lines.append(
            f"- [[file:STAR-GOVDATA-TODO-{number:03d}-jurisdictions.org]"
            f"[STAR-GOVDATA-TODO-{number:03d} Jurisdictions {first} through {last}]]"
        )
    return "\n".join(lines).rstrip() + "\n"


def write_catalog(rows: list[Jurisdiction], output_dir: Path) -> None:
    groups = group_rows(rows)
    output_dir.mkdir(parents=True, exist_ok=True)
    expected = {MASTER_NAME}
    (output_dir / MASTER_NAME).write_text(render_master(), encoding="utf-8")
    for number, codes in enumerate(SHARD_GROUPS, 1):
        name = f"STAR-GOVDATA-TODO-{number:03d}-jurisdictions.org"
        expected.add(name)
        (output_dir / name).write_text(
            render_shard(number, codes, groups),
            encoding="utf-8",
        )
    for stale in output_dir.glob("STAR-GOVDATA-TODO-*-jurisdictions.org"):
        if stale.name not in expected:
            stale.unlink()


def validate_output(output_dir: Path) -> None:
    documents = sorted(output_dir.glob("STAR-GOVDATA-TODO-*.org"))
    text = "".join(path.read_text(encoding="utf-8") for path in documents)
    state_count = len(
        re.findall(
            r"^\* TODO \[[A-Z]{2}/\d{2}\] .* state source catalog ",
            text,
            re.MULTILINE,
        )
    )
    geoids = re.findall(r"^\*\*\* TODO \[(\d{5})\] ", text, re.MULTILINE)
    if len(documents) != len(SHARD_GROUPS) + 1:
        raise ValueError(f"Expected 17 Org files, found {len(documents)}")
    if state_count != EXPECTED_GROUPS:
        raise ValueError(f"Generated {state_count} state TODOs, expected {EXPECTED_GROUPS}")
    if len(geoids) != EXPECTED_ROWS or len(set(geoids)) != EXPECTED_ROWS:
        raise ValueError("Generated county TODO or unique GEOID count is incorrect")
    master = (output_dir / MASTER_NAME).read_text(encoding="utf-8")
    required = (
        "| 0.4.0",
        "=:jurisdiction-completion=",
        "star.govdata.source-profile",
        "valid-through",
    )
    if any(token not in master for token in required):
        raise ValueError("Generated master completion contract is stale")


def main() -> int:
    args = parse_args()
    try:
        rows = validate(parse_rows(read_source(args.input, args.source_url)))
        write_catalog(rows, args.output_dir)
        validate_output(args.output_dir)
    except (OSError, ValueError, urllib.error.URLError, zipfile.BadZipFile) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(
        f"wrote {args.output_dir}: {EXPECTED_GROUPS} state TODOs and "
        f"{EXPECTED_ROWS} county-equivalent TODOs"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
