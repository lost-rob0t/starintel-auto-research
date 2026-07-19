from __future__ import annotations
import datetime as dt
import json
import re
import subprocess
import uuid
from pathlib import Path

TREE_NAMES = ("design", "research", "implement", "indexes")

def project_root() -> Path:
    try:
        result = subprocess.run(["git", "rev-parse", "--show-toplevel"], check=True, capture_output=True, text=True)
        return Path(result.stdout.strip()).resolve()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return Path.cwd().resolve()

def ensure_roam(root: Path | None = None) -> Path:
    roam = (root or project_root()) / "roam"
    roam.mkdir(parents=True, exist_ok=True)
    for tree in TREE_NAMES:
        (roam / tree).mkdir(parents=True, exist_ok=True)
    for ledger in (".implemented", ".rejected"):
        (roam / ledger).touch(exist_ok=True)
    mirror_structure(roam)
    return roam

def visible_dirs(tree: Path) -> set[Path]:
    result = set()
    if tree.exists():
        for path in tree.rglob("*"):
            if path.is_dir():
                rel = path.relative_to(tree)
                if not any(part.startswith(".") for part in rel.parts):
                    result.add(rel)
    return result

def mirror_structure(roam: Path) -> set[Path]:
    for tree in TREE_NAMES:
        (roam / tree).mkdir(parents=True, exist_ok=True)
    rels = set()
    for tree in TREE_NAMES:
        rels.update(visible_dirs(roam / tree))
    for rel in rels:
        for tree in TREE_NAMES:
            (roam / tree / rel).mkdir(parents=True, exist_ok=True)
    return rels

def active_org_files(roam: Path) -> list[Path]:
    return sorted((roam / "implement").rglob("*.org"))

def canonical_from_active(active: Path, roam: Path) -> Path:
    rel = active.resolve().relative_to((roam / "implement").resolve())
    return roam / "design" / rel

def now_iso() -> str:
    return dt.datetime.now().astimezone().isoformat(timespec="seconds")

def append_jsonl(path: Path, value: dict) -> None:
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(value, sort_keys=True) + "\n")

def read_jsonl(path: Path) -> list[dict]:
    values = []
    if not path.exists():
        return values
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"invalid JSONL in {path}:{number}: {exc}") from exc
        if not isinstance(value, dict):
            raise SystemExit(f"invalid ledger record in {path}:{number}")
        values.append(value)
    return values

def new_event_id() -> str:
    return str(uuid.uuid4())

def upsert_header(text: str, key: str, value: str) -> str:
    pattern = re.compile(rf"(?im)^\#\+{re.escape(key)}:\s*.*$")
    line = f"#+{key}: {value}"
    if pattern.search(text):
        return pattern.sub(line, text, count=1)
    lines = text.splitlines()
    insert_at = 0
    while insert_at < len(lines) and (lines[insert_at].startswith("#+") or not lines[insert_at].strip()):
        insert_at += 1
    lines.insert(insert_at, line)
    return "\n".join(lines) + ("\n" if text.endswith("\n") else "")

def org_list(values: list[str], empty: str = "None") -> str:
    return "\n".join(f"- {v}" for v in values) if values else f"- {empty}"

def status_block(event: dict) -> str:
    event_id, status, recorded = event["event_id"], event["status"], event["timestamp"]
    if status == "IMPLEMENTED":
        body = f"""* DONE Implementation Record
:PROPERTIES:
:STATUS_EVENT_ID: {event_id}
:STATUS: IMPLEMENTED
:RECORDED_AT: {recorded}
:END:

** What Was Implemented

{event.get("summary") or "No summary recorded."}

** Files Changed

{org_list(event.get("files", []))}

** Tests

{org_list(event.get("tests", []))}

** Commits

{org_list(event.get("commits", []))}

** Notes

{org_list(event.get("notes", []))}
"""
    else:
        body = f"""* REJECTED Rejection Record
:PROPERTIES:
:STATUS_EVENT_ID: {event_id}
:STATUS: REJECTED
:RECORDED_AT: {recorded}
:END:

** Reason

{event.get("reason") or "No reason recorded."}

** Evidence

{org_list(event.get("evidence", []))}

** Replacement

{event.get("replacement") or "None"}

** Notes

{org_list(event.get("notes", []))}
"""
    return f"\n# STARINTEL-STATUS-BEGIN {event_id}\n{body.strip()}\n# STARINTEL-STATUS-END {event_id}\n"

def apply_event(text: str, event: dict) -> str:
    event_id = event["event_id"]
    begin, end = f"# STARINTEL-STATUS-BEGIN {event_id}", f"# STARINTEL-STATUS-END {event_id}"
    block = status_block(event)
    pattern = re.compile(rf"\n?{re.escape(begin)}.*?{re.escape(end)}\n?", re.S)
    return pattern.sub(block, text, count=1) if pattern.search(text) else text.rstrip() + "\n" + block

def validate_org_headers(path: Path) -> None:
    text = path.read_text(encoding="utf-8")
    missing = [key for key in ("title", "description") if not re.search(rf"(?im)^\#\+{key}:\s*\S", text)]
    if path.suffix.lower() != ".org" or missing:
        raise SystemExit(f"invalid design file {path}; missing: {', '.join(missing)}")
