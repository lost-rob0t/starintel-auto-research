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

# Stable Org-roam shards. Do not regroup based on file size: that would create noisy moves.
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
    "Official identity, home page, canonical domain, aliases, and delegated vendor domains.",
    "Open-data catalogs, data.json, DCAT, CKAN, Socrata, ArcGIS Hub, Huwise/OpenDataSoft, and downloadable bulk files.",
    "GIS, parcel maps, ArcGIS services, OGC services, geospatial downloads, and map viewers.",
    "Legislation, charter, code, ordinances, resolutions, and legal publishing systems.",
    "Meetings, calendars, agendas, packets, minutes, votes, transcripts, recordings, and video archives.",
    "Budgets, annual financial reports, audits, checkbooks, payroll, debt, grants, and revenue records.",
    "Procurement, bids, solicitations, awards, contracts, purchase orders, and vendor-payment systems.",
    "Property, assessment, tax, recorder, deed, parcel, and land-record systems where publicly available.",
    "Courts, dockets, case indexes, and clerk systems where public access is authorized.",
    "Elections, candidates, campaign finance, precincts, results, and voter-information systems.",
    "Public safety, incident, dispatch, jail, inspection, and enforcement datasets where lawfully public.",
    "Permits, licenses, planning, zoning, development, environmental, and code-enforcement systems.",
    "Public-records or FOIA portal, request policy, retention schedules, contacts, and fee rules.",
    "RSS/Atom feeds, alerts, newsletters, sitemaps, robots directives, APIs, exports, and change feeds.",
    "Web archives, retired domains, historical portals, document repositories, and source migrations.",
    "For every route, record platform family, vendor, endpoints, authentication, rate limits, pagination, refresh behavior, coverage dates, raw-artifact policy, provenance locators, and known gaps.",
)

OUTPUT_FIELDS = (
    "official status and verification evidence",
    "source-profile identifier",
    "data family and jurisdiction component",
    "platform and vendor fingerprints",
    "acquisition method and preferred adapter",
    "stable locator and discovery path",
    "access, credential, rate, and legal constraints",
    "earliest and latest observed coverage",
    "raw capture and content hash policy",
    "incremental cursor or reconciliation method",
    "unsupported, missing, inaccessible, or records-request-required state",
    "reviewer and review timestamp",
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
        url, headers={"User-Agent": "starintel-auto-research/1"}
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
    for line_number, line in enumerate(lines[1:] if has_header else lines, start=2 if has_header else 1):
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
    if name.endswith(" Municipio"):
        return "municipio"
    if name.endswith(" Planning Region"):
        return "planning_region"
    if name.endswith(" Census Area"):
        return "census_area"
    if name.endswith(" City and Borough"):
        return "city_and_borough"
    if name.endswith(" Borough"):
        return "borough"
    if name.endswith(" Parish"):
        return "parish"
    if name.lower().endswith(" city"):
        return "independent_city"
    if name.endswith(" District"):
        return "district"
    if name.endswith(" Municipality"):
        return "municipality"
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


def render_shard(number: int, state_codes: tuple[str, ...], groups: dict[str, list[Jurisdiction]]) -> str:
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
        "#+filetags: :starintel:todo:government-data:states:counties:catalog:",
        "#+todo: TODO RESEARCHING REVIEW BLOCKED | DONE REJECTED",
        "",
        "| Version | Date       | Description of change                                      | Did nsaspy approve it |",
        "|---------+------------+------------------------------------------------------------+-----------------------|",
        "| 0.1.0   | 2026-07-28 | Seed state and county-equivalent source-catalog TODO queue | Pending               |",
        "",
        "* Related Nodes",
        "",
        "- [[file:../../indexes/auto-research/STAR-RESEARCH-PIPELINE-INDEX-000-adaptive-research.org][STAR-RESEARCH-PIPELINE-INDEX-000 Adaptive Research]]",
        "- [[file:../../research/auto-research/STAR-RESEARCH-003-us-government-data-acquisition-landscape.org][STAR-RESEARCH-003 U.S. Government Data Acquisition Landscape]]",
        "- [[file:../../design/auto-research/STAR-RESEARCH-PIPELINE-003-government-data-acquisition-actors.org][STAR-RESEARCH-PIPELINE-003 Government Data Acquisition Actors]]",
        "",
        "* Source and Generation",
        "",
        "- Source vintage: 2025 Census Gazetteer county and county-equivalent national file.",
        f"- Source locator: ={SOURCE_URL}=.",
        "- Generated state-level queues: 52 (50 states, District of Columbia, and Puerto Rico).",
        "- Generated county and county-equivalent TODOs: 3,222.",
        "- Regenerate with =tools/generate-government-jurisdiction-todos.py=; do not hand-edit generated jurisdiction shards.",
        "",
        "* Completion Contract",
        "",
        "A jurisdiction TODO reaches =DONE= only after a reviewed source profile records all discovered routes, negative findings, and unresolved gaps. Search results are candidates until official ownership or delegation is verified.",
        "",
        "** Required source routes",
        "",
    ]
    lines.extend(f"{number}. {route}" for number, route in enumerate(SOURCE_ROUTES, 1))
    lines.extend(["", "** Required output fields", ""])
    lines.extend(f"- {field}" for field in OUTPUT_FIELDS)
    lines.extend(["", "* Generated Jurisdiction Shards", ""])
    for number, codes in enumerate(SHARD_GROUPS, 1):
        first, last = STATE_NAMES[codes[0]], STATE_NAMES[codes[-1]]
        lines.append(
            f"- [[file:STAR-GOVDATA-TODO-{number:03d}-jurisdictions.org]"
            f"[STAR-GOVDATA-TODO-{number:03d} Jurisdictions {first} through {last}]]"
        )
    return "\n".join(lines).rstrip() + "\n"


def write_catalog(rows: list[Jurisdiction], output_dir: Path) -> None:
    groups = group_rows(rows)
    output_dir.mkdir(parents=True, exist_ok=True)
    expected = {"STAR-GOVDATA-TODO-000-jurisdiction-source-catalog.org"}
    (output_dir / "STAR-GOVDATA-TODO-000-jurisdiction-source-catalog.org").write_text(
        render_master(), encoding="utf-8"
    )
    for number, codes in enumerate(SHARD_GROUPS, 1):
        name = f"STAR-GOVDATA-TODO-{number:03d}-jurisdictions.org"
        expected.add(name)
        (output_dir / name).write_text(render_shard(number, codes, groups), encoding="utf-8")
    for stale in output_dir.glob("STAR-GOVDATA-TODO-*-jurisdictions.org"):
        if stale.name not in expected:
            stale.unlink()


def validate_output(output_dir: Path) -> None:
    documents = sorted(output_dir.glob("STAR-GOVDATA-TODO-*.org"))
    text = "".join(path.read_text(encoding="utf-8") for path in documents)
    state_count = len(
        re.findall(r"^\* TODO \[[A-Z]{2}/\d{2}\] .* state source catalog ", text, re.MULTILINE)
    )
    geoids = re.findall(r"^\*\*\* TODO \[(\d{5})\] ", text, re.MULTILINE)
    if len(documents) != len(SHARD_GROUPS) + 1:
        raise ValueError(f"Expected 17 Org files, found {len(documents)}")
    if state_count != EXPECTED_GROUPS:
        raise ValueError(f"Generated {state_count} state TODOs, expected {EXPECTED_GROUPS}")
    if len(geoids) != EXPECTED_ROWS or len(set(geoids)) != EXPECTED_ROWS:
        raise ValueError("Generated county TODO or unique GEOID count is incorrect")


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
