#!/usr/bin/env python3
"""Deterministic child-identity firewall for StarIntel artifacts.

This module is intentionally network-free. It sanitizes structured payloads,
blocks child-name queries and child identity targets, verifies named adult
identity targets, and scans exports for privacy leaks.

It never includes prohibited values in violations or logs.
"""

from __future__ import annotations

import argparse
import copy
import json
import re
import sys
from collections import Counter
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Iterable, Mapping, MutableMapping, Sequence


REDACTED_CHILD = "[CHILD]"
REJECTED_QUERY = "[REJECTED UNSAFE QUERY]"

CHILD_ROLE_TOKENS = {
    "child",
    "child-victim",
    "child-survivor",
    "juvenile",
    "minor",
    "minor-victim",
    "minor-survivor",
}

NAME_KEYS = {
    "name",
    "full_name",
    "first_name",
    "middle_name",
    "last_name",
    "birth_name",
    "former_name",
    "nickname",
    "initials",
    "alias",
    "aliases",
}

DIRECT_IDENTIFIER_KEYS = NAME_KEYS | {
    "date_of_birth",
    "dob",
    "birth_date",
    "home_address",
    "address",
    "street_address",
    "school",
    "school_name",
    "daycare",
    "daycare_name",
    "classroom",
    "hospital_room",
    "medical_record_number",
    "mrn",
    "phone",
    "phone_number",
    "email",
    "email_address",
    "social_account",
    "social_handle",
    "username",
    "photo",
    "photograph",
    "image",
    "image_url",
    "biometric_identifier",
    "precise_coordinates",
    "latitude",
    "longitude",
}

QUERY_KEYS = {
    "query",
    "search_query",
    "archive_query",
    "court_query",
    "web_query",
    "news_query",
}

PROHIBITED_QUERY_FIELD_KEYS = {
    "child_name",
    "victim_name",
    "minor_name",
    "child_alias",
    "child_initials",
}

IDENTITY_TARGET_KEYS = {
    "identity_resolution_target",
    "identity_target",
    "publish_named_identity",
    "named_target",
}

ADULT_LEGAL_STATUSES = {
    "charged",
    "indicted",
    "pleaded-guilty",
    "pleaded-no-contest",
    "convicted",
    "sentenced",
    "final-public-agency-finding",
}

AGE_BANDS = (
    (0, 0, "under-1"),
    (1, 4, "1-4"),
    (5, 9, "5-9"),
    (10, 13, "10-13"),
    (14, 17, "14-17"),
)

CASE_LOCAL_CHILD_ID = re.compile(
    r"^starintel:child-case-local:[A-Za-z0-9._:-]+:[0-9]{2,}$"
)


@dataclass(frozen=True)
class Violation:
    """A privacy finding that never contains the prohibited value."""

    code: str
    path: str
    action: str
    blocking: bool


@dataclass
class FirewallResult:
    allowed: bool
    sanitized: Any
    violations: list[Violation]
    redaction_counts: dict[str, int]

    def as_dict(self) -> dict[str, Any]:
        return {
            "allowed": self.allowed,
            "sanitized": self.sanitized,
            "violations": [asdict(item) for item in self.violations],
            "redaction_counts": dict(sorted(self.redaction_counts.items())),
        }


class ChildIdentityFirewall:
    """Apply the approved Child Identity Firewall deterministically."""

    def __init__(
        self,
        *,
        case_id: str,
        known_child_identifiers: Iterable[str] = (),
    ) -> None:
        if not case_id or not case_id.strip():
            raise ValueError("case_id is required")
        self.case_id = self._safe_case_id(case_id)
        self.known_child_identifiers = tuple(
            sorted(
                {
                    value.strip()
                    for value in known_child_identifiers
                    if isinstance(value, str) and value.strip()
                },
                key=len,
                reverse=True,
            )
        )
        self._violations: list[Violation] = []
        self._redactions: Counter[str] = Counter()
        self._child_ordinal = 0

    def sanitize(self, payload: Any) -> FirewallResult:
        """Return a sanitized copy and a fail-closed decision."""

        self._violations = []
        self._redactions = Counter()
        self._child_ordinal = 0
        sanitized = self._walk(copy.deepcopy(payload), path="$", child_context=False)
        self._scan_export(sanitized, path="$", add_violations=True)
        allowed = not any(item.blocking for item in self._violations)
        return FirewallResult(
            allowed=allowed,
            sanitized=sanitized,
            violations=list(self._violations),
            redaction_counts=dict(self._redactions),
        )

    def scan_export(self, payload: Any) -> FirewallResult:
        """Scan an already-produced export without mutating it."""

        self._violations = []
        self._redactions = Counter()
        self._scan_export(payload, path="$", add_violations=True)
        return FirewallResult(
            allowed=not any(item.blocking for item in self._violations),
            sanitized=copy.deepcopy(payload),
            violations=list(self._violations),
            redaction_counts={},
        )

    def _walk(self, value: Any, *, path: str, child_context: bool) -> Any:
        if isinstance(value, MutableMapping):
            return self._walk_mapping(value, path=path, inherited_child=child_context)
        if isinstance(value, list):
            return [
                self._walk(item, path=f"{path}[{index}]", child_context=child_context)
                for index, item in enumerate(value)
            ]
        if isinstance(value, tuple):
            return tuple(
                self._walk(item, path=f"{path}[{index}]", child_context=child_context)
                for index, item in enumerate(value)
            )
        if isinstance(value, str):
            return self._redact_known_identifiers(value, path=path)
        return value

    def _walk_mapping(
        self,
        value: MutableMapping[str, Any],
        *,
        path: str,
        inherited_child: bool,
    ) -> dict[str, Any]:
        normalized = {str(key): item for key, item in value.items()}
        child_context = inherited_child or self._mapping_is_child(normalized)
        identity_target = self._mapping_is_identity_target(normalized)

        if identity_target:
            self._enforce_identity_target(normalized, path=path, child_context=child_context)

        output: dict[str, Any] = {}
        child_pseudonym: str | None = None
        if child_context:
            child_pseudonym = self._case_local_pseudonym()

        for key, item in normalized.items():
            lower_key = key.lower()
            item_path = f"{path}.{key}"

            if lower_key in PROHIBITED_QUERY_FIELD_KEYS:
                self._record(
                    "child-query-field",
                    item_path,
                    "removed prohibited child query field",
                    blocking=True,
                )
                self._redactions["query-field"] += 1
                continue

            if lower_key in QUERY_KEYS:
                query = item if isinstance(item, str) else json.dumps(item, sort_keys=True)
                if child_context or self._contains_known_identifier(query):
                    output[key] = REJECTED_QUERY
                    self._record(
                        "unsafe-child-query",
                        item_path,
                        "rejected child-identity query",
                        blocking=True,
                    )
                    self._redactions["query"] += 1
                else:
                    output[key] = self._walk(item, path=item_path, child_context=False)
                continue

            if child_context and lower_key in DIRECT_IDENTIFIER_KEYS:
                self._record(
                    "child-direct-identifier",
                    item_path,
                    "removed prohibited child identifier",
                    blocking=False,
                )
                self._redactions[lower_key] += 1
                continue

            if child_context and lower_key == "age":
                age_band = self._age_band(item)
                output["age_band"] = age_band
                self._record(
                    "child-exact-age",
                    item_path,
                    "generalized exact child age",
                    blocking=False,
                )
                self._redactions["exact-age"] += 1
                continue

            if child_context and lower_key in {"id", "person_id", "subject_id"}:
                if isinstance(item, str) and CASE_LOCAL_CHILD_ID.fullmatch(item):
                    output[key] = item
                else:
                    output[key] = child_pseudonym
                    self._record(
                        "cross-case-child-id",
                        item_path,
                        "replaced non-case-local child identifier",
                        blocking=True,
                    )
                    self._redactions["child-id"] += 1
                continue

            if child_context and lower_key == "display_name":
                output[key] = self._display_name(child_pseudonym)
                if item != output[key]:
                    self._record(
                        "child-display-name",
                        item_path,
                        "replaced child display name with case-local pseudonym",
                        blocking=False,
                    )
                    self._redactions["display-name"] += 1
                continue

            output[key] = self._walk(
                item,
                path=item_path,
                child_context=child_context and lower_key not in {"adult_defendant", "adult_target"},
            )

        if child_context:
            output.setdefault("id", child_pseudonym)
            output.setdefault("display_name", self._display_name(child_pseudonym))
            output["public_identity_prohibited"] = True
            output["cross_case_linkage_prohibited"] = True
            if "age_band" not in output:
                output["age_band"] = "unknown-child"

        return output

    def _mapping_is_child(self, value: Mapping[str, Any]) -> bool:
        if value.get("public_identity_prohibited") is True:
            return True
        if value.get("is_child") is True or value.get("minor") is True:
            return True

        age = value.get("age")
        if isinstance(age, (int, float)) and not isinstance(age, bool) and age < 18:
            return True

        age_at_event = value.get("age_at_event")
        if (
            isinstance(age_at_event, (int, float))
            and not isinstance(age_at_event, bool)
            and age_at_event < 18
        ):
            return True

        if str(value.get("age_band", "")).lower() in {
            "under-1",
            "1-4",
            "5-9",
            "10-13",
            "14-17",
            "unknown-child",
        }:
            return True

        role_values: list[str] = []
        for key in ("role", "person_role", "subject_role", "target_role"):
            raw = value.get(key)
            if isinstance(raw, str):
                role_values.append(raw.lower())
            elif isinstance(raw, Sequence) and not isinstance(raw, (str, bytes)):
                role_values.extend(str(item).lower() for item in raw)
        return any(role in CHILD_ROLE_TOKENS for role in role_values)

    def _mapping_is_identity_target(self, value: Mapping[str, Any]) -> bool:
        if any(value.get(key) is True for key in IDENTITY_TARGET_KEYS):
            return True
        target_type = str(value.get("target_type", "")).lower()
        return target_type in {"named-person", "adult-defendant", "adult-offender"}

    def _enforce_identity_target(
        self,
        value: MutableMapping[str, Any],
        *,
        path: str,
        child_context: bool,
    ) -> None:
        if child_context:
            self._record(
                "named-child-target",
                path,
                "blocked child or minor identity target",
                blocking=True,
            )
            return

        age = value.get("age_at_event", value.get("age"))
        adult_status = str(value.get("adult_status", "")).lower()
        adult_verified = (
            isinstance(age, (int, float))
            and not isinstance(age, bool)
            and age >= 18
        ) or adult_status in {"verified", "authoritative-verified"}

        if not adult_verified:
            self._record(
                "adult-status-unverified",
                path,
                "blocked named target until adult status is verified",
                blocking=True,
            )

        legal_status = str(value.get("legal_status", "")).lower().replace("_", "-")
        if legal_status not in ADULT_LEGAL_STATUSES:
            self._record(
                "adult-legal-status-insufficient",
                path,
                "blocked named target below approved legal-status threshold",
                blocking=True,
            )

    def _scan_export(self, value: Any, *, path: str, add_violations: bool) -> None:
        if isinstance(value, Mapping):
            child_context = self._mapping_is_child(value)
            for key, item in value.items():
                item_path = f"{path}.{key}"
                lower_key = str(key).lower()
                if child_context and lower_key in DIRECT_IDENTIFIER_KEYS:
                    if add_violations:
                        self._record(
                            "export-child-identifier-key",
                            item_path,
                            "blocked export containing child identifier field",
                            blocking=True,
                        )
                if child_context and lower_key == "age":
                    if add_violations:
                        self._record(
                            "export-child-exact-age",
                            item_path,
                            "blocked export containing exact child age",
                            blocking=True,
                        )
                if child_context and lower_key in {"id", "person_id", "subject_id"}:
                    if not isinstance(item, str) or not CASE_LOCAL_CHILD_ID.fullmatch(item):
                        if add_violations:
                            self._record(
                                "export-cross-case-child-id",
                                item_path,
                                "blocked export containing non-case-local child identifier",
                                blocking=True,
                            )
                self._scan_export(item, path=item_path, add_violations=add_violations)
            return

        if isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
            for index, item in enumerate(value):
                self._scan_export(item, path=f"{path}[{index}]", add_violations=add_violations)
            return

        if isinstance(value, str) and self._contains_known_identifier(value):
            if add_violations:
                self._record(
                    "export-known-child-identifier",
                    path,
                    "blocked export containing known child identifier",
                    blocking=True,
                )

    def _redact_known_identifiers(self, text: str, *, path: str) -> str:
        result = text
        redacted = 0
        for identifier in self.known_child_identifiers:
            pattern = re.compile(re.escape(identifier), flags=re.IGNORECASE)
            result, count = pattern.subn(REDACTED_CHILD, result)
            redacted += count
        if redacted:
            self._record(
                "known-child-identifier",
                path,
                "redacted known child identifier",
                blocking=False,
            )
            self._redactions["known-child-identifier"] += redacted
        return result

    def _contains_known_identifier(self, text: str) -> bool:
        lowered = text.casefold()
        return any(identifier.casefold() in lowered for identifier in self.known_child_identifiers)

    def _record(self, code: str, path: str, action: str, *, blocking: bool) -> None:
        finding = Violation(code=code, path=path, action=action, blocking=blocking)
        if finding not in self._violations:
            self._violations.append(finding)

    def _case_local_pseudonym(self) -> str:
        self._child_ordinal += 1
        return f"starintel:child-case-local:{self.case_id}:{self._child_ordinal:02d}"

    @staticmethod
    def _display_name(identifier: str | None) -> str:
        if not identifier:
            return "Child victim"
        ordinal = identifier.rsplit(":", 1)[-1]
        return f"Child victim {ordinal}"

    @staticmethod
    def _age_band(value: Any) -> str:
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return "unknown-child"
        age = int(value)
        for minimum, maximum, label in AGE_BANDS:
            if minimum <= age <= maximum:
                return label
        return "unknown-child"

    @staticmethod
    def _safe_case_id(case_id: str) -> str:
        safe = re.sub(r"[^A-Za-z0-9._:-]+", "-", case_id.strip()).strip("-")
        if not safe:
            raise ValueError("case_id does not contain a usable identifier")
        return safe


def _load_identifiers(path: str | None) -> list[str]:
    if not path:
        return []
    text = Path(path).read_text(encoding="utf-8")
    try:
        parsed = json.loads(text)
    except json.JSONDecodeError:
        return [line.strip() for line in text.splitlines() if line.strip()]
    if not isinstance(parsed, list) or not all(isinstance(item, str) for item in parsed):
        raise ValueError("known identifiers file must contain a JSON string list or one value per line")
    return parsed


def _read_json(path: str) -> Any:
    if path == "-":
        return json.load(sys.stdin)
    with Path(path).open("r", encoding="utf-8") as handle:
        return json.load(handle)


def _write_json(path: str, payload: Any) -> None:
    if path == "-":
        json.dump(payload, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
        return
    with Path(path).open("w", encoding="utf-8") as handle:
        json.dump(payload, handle, indent=2, sort_keys=True)
        handle.write("\n")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("sanitize", "scan"))
    parser.add_argument("input", help="JSON input path or - for stdin")
    parser.add_argument("output", help="JSON output path or - for stdout")
    parser.add_argument("--case-id", required=True)
    parser.add_argument("--known-child-identifiers-file")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        identifiers = _load_identifiers(args.known_child_identifiers_file)
        payload = _read_json(args.input)
        firewall = ChildIdentityFirewall(
            case_id=args.case_id,
            known_child_identifiers=identifiers,
        )
        result = firewall.sanitize(payload) if args.command == "sanitize" else firewall.scan_export(payload)
        _write_json(args.output, result.as_dict())
        return 0 if result.allowed else 2
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"child identity firewall failed: {type(error).__name__}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
