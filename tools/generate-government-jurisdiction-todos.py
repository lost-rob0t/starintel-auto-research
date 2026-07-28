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
GENERATED_DATE = "2026-07-28"
DEFAULT_OUTPUT = Path("roam/todos/government-data")
MAX_SHARD_BYTES = 48_000

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
    parser.add_argument("--max-shard-bytes", type=int, default=MAX_SHARD_BYTES)
    return parser.parse_args()


def fetch_source(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "starintel-auto-research/1"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def read_source(path: Path | None, url: str) -> str:
    data = path.read_bytes() if path else fetch_source(url)
    is_zip = (path and path.suffix.lower() == ".zip") or data.startswith(b"PK\x03\x04")
    if is_zip:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            names = archive.namelist()
            member = SOURCE_MEMBER if SOURCE_MEMBER in names else names[0]
            data = archive.read(member)
    for encoding in ("utf-8-sig", "latin-1"):
        try:
            return data.decode(encoding)
        except UnicodeDecodeError:
            pass
    raise ValueError("Unable to decode Census source")


def parse_rows(text: str) -> list[Jurisdiction]:
    lines = [line.strip() for line in text.replace("\r", "").splitlines() if line.strip()]
    if not lines:
        raise ValueError("Census source is empty")
    first = lines[0].split("|")
    has_header = first[:2] == ["USPS", "GEOID"]
    data_lines = lines[1:] if has_header else lines
    rows: list[Jurisdiction] = []
    for line_number, line in enumerate(data_lines, start=2 if has_header else 1):
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
    if len(set(geoids)) != len(geoids):
        raise ValueError("Duplicate county-equivalent GEOIDs")
    for row in result:
        if row.usps not in STATE_NAMES:
            raise ValueError(f"Unknown USPS group: {row.usps}")
        if len(row.geoid) != 5 or not row.geoid.isdigit():
            raise ValueError(f"Invalid GEOID: {row.geoid}")
        if not row.name:
            raise ValueError(f"Missing name for GEOID {row.geoid}")
    groups = {row.usps for row in result}
    if len(groups) != EXPECTED_GROUPS or groups != set(STATE_NAMES):
        raise ValueError("State/territory group set does not match the expected 52 groups")
    return result


def jurisdiction_type(name: str) -> str:
    if name.endswith(" Municipio"):
        return "municipio"
    if name.endswith(" Planning Region"):
        return "planning-region"
    if name.endswith(" Census Area"):
        return "census-area"
    if name.endswith(" City and Borough"):
        return "city-and-borough"
    if name.endswith(" Borough"):
        return "borough"
    if name.endswith(" Parish"):
        return "parish"
    if name.lower().endswith(" city"):
        return "independent-city"
    if name.endswith(" District"):
        return "district"
    if name.endswith(" Municipality"):
        return "municipality"
    return "county"


def group_rows(rows: list[Jurisdiction]) -> tuple[list[str], dict[str, list[Jurisdiction]]]:
    groups: dict[str, list[Jurisdiction]] = defaultdict(list)
    for row in rows:
        groups[row.usps].append(row)
    for state_rows in groups.values():
        state_rows.sort(key=lambda row: row.geoid)
    order = sorted(groups, key=lambda usps: int(groups[usps][0].state_fips))
    return order, groups


def render_state_block(usps: str, rows: list[Jurisdiction]) -> str:
    state_fips = rows[0].state_fips
    out = [
        f"* TODO {STATE_NAMES[usps]} state source catalog",
        ":PROPERTIES:",
        f":USPS:      {usps}",
        f":STATE_FIPS: {state_fips}",
        ":SCOPE:     state",
        f":COUNTY_EQUIVALENTS: {len(rows)}",
        ":CHECKLIST: jurisdiction-source-profile-v1",
        ":END:",
        "- [ ] Verify the state or territory identity spine and official domains.",
        "- [ ] Catalog statewide portals, shared services, and state-mandated local systems.",
        "- [ ] Record state-specific public-records law, retention, and access constraints.",
        "- [ ] Review every county or county-equivalent TODO below.",
        "",
        "** County and county-equivalent TODOs",
        "",
    ]
    for row in rows:
        out.extend(
            [
                f"*** TODO {row.name}",
                ":PROPERTIES:",
                f":GEOID:     {row.geoid}",
                f":USPS:      {row.usps}",
                f":STATE_FIPS: {row.state_fips}",
                ":SCOPE:     county-equivalent",
                f":TYPE:      {jurisdiction_type(row.name)}",
                ":CHECKLIST: jurisdiction-source-profile-v1",
                ":END:",
                "",
            ]
        )
    return "\n".join(out).rstrip() + "\n"


def partition_blocks(order: list[str], groups: dict[str, list[Jurisdiction]], limit: int) -> list[list[str]]:
    shards: list[list[str]] = []
    current: list[str] = []
    size = 0
    for usps in order:
        block = render_state_block(usps, groups[usps])
        block_size = len(block.encode("utf-8"))
        if current and size + block_size > limit:
            shards.append(current)
            current = []
            size = 0
        current.append(usps)
        size += block_size
    if current:
        shards.append(current)
    return shards


def render_shard(number: int, state_codes: list[str], groups: dict[str, list[Jurisdiction]]) -> str:
    slug = f"{number:03d}"
    first = STATE_NAMES[state_codes[0]]
    last = STATE_NAMES[state_codes[-1]]
    header = [
        ":PROPERTIES:",
        f":ID:       starintel-government-data-jurisdiction-todos-{slug}",
        ":END:",
        f"#+title: STAR-GOVDATA-TODO-{slug} Jurisdictions {first} through {last}",
        "#+description: Generated state and county-equivalent TODO shard from the 2025 Census Gazetteer roster.",
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
    return "\n".join(header) + "\n".join(render_state_block(code, groups[code]) for code in state_codes)


def render_master(shards: list[list[str]]) -> str:
    out = [
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
        f"| 0.1.0   | {GENERATED_DATE} | Seed state and county-equivalent source-catalog TODO queue | Pending               |",
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
    out.extend(f"{number}. {route}" for number, route in enumerate(SOURCE_ROUTES, 1))
    out.extend(["", "** Required output fields", ""])
    out.extend(f"- {field}" for field in OUTPUT_FIELDS)
    out.extend(["", "* Generated Jurisdiction Shards", ""])
    for number, state_codes in enumerate(shards, 1):
        slug = f"{number:03d}"
        first = STATE_NAMES[state_codes[0]]
        last = STATE_NAMES[state_codes[-1]]
        out.append(
            f"- [[file:STAR-GOVDATA-TODO-{slug}-jurisdictions.org]"
            f"[STAR-GOVDATA-TODO-{slug} Jurisdictions {first} through {last}]]"
        )
    return "\n".join(out).rstrip() + "\n"


def write_catalog(rows: list[Jurisdiction], output_dir: Path, max_shard_bytes: int) -> None:
    order, groups = group_rows(rows)
    shards = partition_blocks(order, groups, max_shard_bytes)
    output_dir.mkdir(parents=True, exist_ok=True)
    expected_names = set()
    for number, state_codes in enumerate(shards, 1):
        name = f"STAR-GOVDATA-TODO-{number:03d}-jurisdictions.org"
        expected_names.add(name)
        (output_dir / name).write_text(render_shard(number, state_codes, groups), encoding="utf-8")
    master_name = "STAR-GOVDATA-TODO-000-jurisdiction-source-catalog.org"
    expected_names.add(master_name)
    (output_dir / master_name).write_text(render_master(shards), encoding="utf-8")
    for stale in output_dir.glob("STAR-GOVDATA-TODO-*-jurisdictions.org"):
        if stale.name not in expected_names:
            stale.unlink()


def validate_output(output_dir: Path) -> None:
    documents = [output_dir / "STAR-GOVDATA-TODO-000-jurisdiction-source-catalog.org"]
    documents.extend(sorted(output_dir.glob("STAR-GOVDATA-TODO-???-jurisdictions.org")))
    text = "".join(path.read_text(encoding="utf-8") for path in documents)
    state_count = len(re.findall(r"^\* TODO .* state source catalog$", text, re.MULTILINE))
    county_count = len(re.findall(r"^\*\*\* TODO ", text, re.MULTILINE))
    geoids = re.findall(r"^:GEOID:\s+(\d{5})$", text, re.MULTILINE)
    if state_count != EXPECTED_GROUPS:
        raise ValueError(f"Generated {state_count} state TODOs, expected {EXPECTED_GROUPS}")
    if county_count != EXPECTED_ROWS or len(set(geoids)) != EXPECTED_ROWS:
        raise ValueError("Generated county TODO or unique GEOID count is incorrect")


def main() -> int:
    args = parse_args()
    try:
        rows = validate(parse_rows(read_source(args.input, args.source_url)))
        write_catalog(rows, args.output_dir, args.max_shard_bytes)
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
