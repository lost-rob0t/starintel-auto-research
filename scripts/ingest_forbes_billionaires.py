#!/usr/bin/env python3
"""Fetch Forbes' real-time billionaire ranking and write deterministic JSONL."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import tempfile
import time
from datetime import UTC, datetime
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode
from urllib.request import Request, urlopen

ENDPOINT = "https://www.forbes.com/forbesapi/person/rtb/0/position/true.json"
SOURCE_URL = "https://www.forbes.com/real-time-billionaires/"
DATASET = "forbes-real-time-billionaires"
USER_AGENT = "StarIntel-Forbes-RTB-Ingest/1.0"
MAX_BYTES = 64 * 1024 * 1024


class IngestError(RuntimeError):
    pass


def fetch(limit: int, timeout: float, retries: int) -> tuple[dict[str, Any], str]:
    url = f"{ENDPOINT}?{urlencode({'limit': limit})}"
    last_error: BaseException | None = None

    for attempt in range(retries + 1):
        request = Request(
            url,
            headers={
                "Accept": "application/json",
                "Referer": SOURCE_URL,
                "User-Agent": USER_AGENT,
            },
        )
        try:
            with urlopen(request, timeout=timeout) as response:
                body = response.read(MAX_BYTES + 1)
            if len(body) > MAX_BYTES:
                raise IngestError("Forbes response exceeded 64 MiB")
            if body.lstrip().startswith(b"<"):
                raise IngestError("Forbes returned HTML instead of JSON")
            payload = json.loads(body)
            if not isinstance(payload, dict):
                raise IngestError("Forbes response is not a JSON object")
            return payload, url
        except HTTPError as exc:
            last_error = exc
            if exc.code != 429 and not 500 <= exc.code <= 599:
                raise IngestError(f"Forbes returned HTTP {exc.code}") from exc
        except (URLError, TimeoutError, OSError, json.JSONDecodeError) as exc:
            last_error = exc

        if attempt < retries:
            time.sleep(min(2**attempt, 16))

    raise IngestError(f"Forbes request failed after {retries + 1} attempts") from last_error


def extract(payload: dict[str, Any]) -> list[dict[str, Any]]:
    paths = (
        ("personList", "personsLists"),
        ("personList", "persons"),
        ("personsLists",),
        ("persons",),
        ("data",),
    )
    for path in paths:
        value: Any = payload
        for key in path:
            if not isinstance(value, dict):
                value = None
                break
            value = value.get(key)
        if isinstance(value, list):
            records = [item for item in value if isinstance(item, dict)]
            if records:
                return records
    raise IngestError("Forbes response schema changed: no person list found")


def clean(value: Any) -> str:
    return " ".join(str(value or "").split())


def number(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def integer(value: Any) -> int | None:
    value = number(value)
    return int(value) if value is not None else None


def usd(value: Any) -> int | None:
    value = number(value)
    return round(value * 1_000_000) if value is not None else None


def normalize(record: dict[str, Any], retrieved_at: str) -> dict[str, Any]:
    name = clean(record.get("personName"))
    if not name:
        raise IngestError("record is missing personName")

    uri = clean(record.get("uri"))
    country = clean(record.get("countryOfCitizenship"))
    wealth_source = clean(record.get("source"))
    identity = uri or f"{name}|{country}|{wealth_source}"
    digest = hashlib.sha256(identity.encode()).hexdigest()

    industries = record.get("industries")
    if not isinstance(industries, list):
        industries = [industries] if industries else []

    rank = integer(record.get("rank")) or integer(record.get("position"))
    worth = usd(record.get("finalWorth"))
    previous = usd(record.get("estWorthPrev"))
    profile = f"https://www.forbes.com/profile/{uri}/" if uri else None

    doc = {
        "_id": f"person:forbes:{digest}",
        "dataset": DATASET,
        "dtype": "person",
        "version": "0.8.0",
        "name": name,
        "forbes_uri": uri or None,
        "forbes_profile_url": profile,
        "rank": rank,
        "net_worth_usd": worth,
        "previous_net_worth_usd": previous,
        "net_worth_change_usd": worth - previous if worth is not None and previous is not None else None,
        "wealth_source": wealth_source or None,
        "industries": [clean(item) for item in industries if clean(item)],
        "country_of_citizenship": country or None,
        "gender": clean(record.get("gender")) or None,
        "retrieved_at": retrieved_at,
        "sources": [SOURCE_URL] + ([profile] if profile else []),
    }
    return {key: value for key, value in doc.items() if value is not None}


def atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, delete=False) as handle:
        temporary = Path(handle.name)
        handle.write(data)
        handle.flush()
        os.fsync(handle.fileno())
    temporary.replace(path)


def ingest(payload: dict[str, Any], output: Path, min_records: int, api_url: str) -> dict[str, Any]:
    records = extract(payload)
    if len(records) < min_records:
        raise IngestError(f"refusing suspicious result set of {len(records)} records")

    retrieved_at = datetime.now(tz=UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    documents = [normalize(record, retrieved_at) for record in records]
    documents.sort(key=lambda doc: (doc.get("rank") is None, doc.get("rank", 10**9), doc["_id"]))

    ids = [doc["_id"] for doc in documents]
    if len(ids) != len(set(ids)):
        raise IngestError("duplicate normalized document IDs")

    body = b"".join(
        json.dumps(doc, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode() + b"\n"
        for doc in documents
    )
    atomic_write(output / "latest.jsonl", body)

    manifest = {
        "dataset": DATASET,
        "source": SOURCE_URL,
        "api": api_url,
        "retrieved_at": retrieved_at,
        "record_count": len(documents),
        "sha256": hashlib.sha256(body).hexdigest(),
        "file": "latest.jsonl",
    }
    atomic_write(output / "manifest.json", (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode())
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=Path("datasets/forbes-real-time-billionaires"))
    parser.add_argument("--limit", type=int, default=3000)
    parser.add_argument("--min-records", type=int, default=100)
    parser.add_argument("--timeout", type=float, default=30)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--input-json", type=Path)
    args = parser.parse_args()

    try:
        if args.input_json:
            payload = json.loads(args.input_json.read_text(encoding="utf-8"))
            api_url = str(args.input_json)
        else:
            payload, api_url = fetch(args.limit, args.timeout, args.retries)
        manifest = ingest(payload, args.output, args.min_records, api_url)
    except (IngestError, OSError, json.JSONDecodeError) as exc:
        print(f"error: {exc}", file=os.sys.stderr)
        return 1

    print(json.dumps(manifest, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
