#!/usr/bin/env python3
"""Deterministic Child Identity Firewall for StarIntel artifacts.

The module is network-free. It sanitizes structured inputs, blocks child-name
queries and child identity targets, verifies named adult targets, and scans
exports for prohibited child identifiers. Findings never echo prohibited data.
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

CHILD_ROLES = {
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

CHILD_IDENTIFIER_KEYS = NAME_KEYS | {
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

PROHIBITED_QUERY_FIELDS = {
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


@dataclass(frozen=True)
class Violation:
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
    """Enforce the approved child identity boundary."""

    def __init__(
        self,
        *,
        case_id: str,
        known_child_identifiers: Iterable[str] = (),
    ) -> None:
        self.case_id = self._safe_case_id(case_id)
        self.known_child_identifiers = tuple(
            sorted(
                {
                    item.strip()
                    for item in known_child_identifiers
                    if isinstance(item, str) and item.strip()
                },
                key=len,
                reverse=True,
            )
        )
        self._violations: list[Violation] = []
        self._redactions: Counter[str] = Counter()
        self._child_ordinal = 0

    def sanitize(self, payload: Any) -> FirewallResult:
        self._reset()
        sanitized = self._walk(copy.deepcopy(payload), path="$", inherited_child=False)
        self._scan_export(sanitized, path="$", inherited_child=False)
        return self._result(sanitized)

    def scan_export(self, payload: Any) -> FirewallResult:
        self._reset()
        copied = copy.deepcopy(payload)
        self._scan_export(copied, path="$", inherited_child=False)
        return self._result(copied)

    def _reset(self) -> None:
        self._violations = []
        self._redactions = Counter()
        self._child_ordinal = 0

    def _result(self, sanitized: Any) -> FirewallResult:
        return FirewallResult(
            allowed=not any(item.blocking for item in self._violations),
            sanitized=sanitized,
            violations=list(self._violations),
            redaction_counts=dict(self._redactions),
        )

    def _walk(self, value: Any, *, path: str, inherited_child: bool) -> Any:
        if isinstance(value, MutableMapping):
            return self._walk_mapping(value, path=path, inherited_child=inherited_child)
        if isinstance(value, list):
            return [
                self._walk(item, path=f"{path}[{index}]", inherited_child=inherited_child)
                for index, item in enumerate(value)
            ]
        if isinstance(value, tuple):
            return tuple(
                self._walk(item, path=f"{path}[{index}]", inherited_child=inherited_child)
                for index, item in enumerate(value)
            )
        if isinstance(value, str):
            return self._redact_known(value, path=path)
        return value

    def _walk_mapping(
        self,
        value: MutableMapping[str, Any],
        *,
        path: str,
        inherited_child: bool,
    ) -> dict[str, Any]:
        normalized = {str(key): item for key, item in value.items()}
        direct_child = self._is_child(normalized)
        child_context = inherited_child or direct_child
        identity_target = self._is_identity_target(normalized)
        verified_adult: bool | None = None

        if identity_target:
            verified_adult = self._enforce_identity_target(
                normalized,
                path=path,
                is_child=direct_child,
            )

        pseudonym = self._new_child_id() if direct_child else None
        output: dict[str, Any] = {}

        for key, item in normalized.items():
            lower = key.lower()
            item_path = f"{path}.{key}"

            if lower in PROHIBITED_QUERY_FIELDS:
                self._record(
                    "child-query-field",
                    item_path,
                    "removed prohibited child query field",
                    blocking=True,
                )
                self._redactions["query-field"] += 1
                continue

            if lower in QUERY_KEYS:
                serialized = item if isinstance(item, str) else json.dumps(item, sort_keys=True)
                if child_context or self._contains_known(serialized):
                    output[key] = REJECTED_QUERY
                    self._record(
                        "unsafe-child-query",
                        item_path,
                        "rejected child-identity query",
                        blocking=True,
                    )
                    self._redactions["query"] += 1
                else:
                    output[key] = self._walk(item, path=item_path, inherited_child=False)
                continue

            if identity_target and verified_adult is False and lower in NAME_KEYS:
                self._record(
                    "unverified-target-identifier",
                    item_path,
                    "removed name until adult status is verified",
                    blocking=True,
                )
                self._redactions["unverified-target-name"] += 1
                continue

            if child_context and lower in CHILD_IDENTIFIER_KEYS:
                self._record(
                    "child-direct-identifier",
                    item_path,
                    "removed prohibited child identifier",
                    blocking=False,
                )
                self._redactions[lower] += 1
                continue

            if direct_child and lower == "age":
                output["age_band"] = self._age_band(item)
                self._record(
                    "child-exact-age",
                    item_path,
                    "generalized exact child age",
                    blocking=False,
                )
                self._redactions["exact-age"] += 1
                continue

            if direct_child and lower in {"id", "person_id", "subject_id"}:
                if isinstance(item, str) and self._is_current_case_child_id(item):
                    output[key] = item
                    pseudonym = item
                else:
                    output[key] = pseudonym
                    self._record(
                        "cross-case-child-id",
                        item_path,
                        "replaced non-current-case child identifier",
                        blocking=True,
                    )
                    self._redactions["child-id"] += 1
                continue

            if direct_child and lower == "display_name":
                replacement = self._display_name(pseudonym)
                output[key] = replacement
                if item != replacement:
                    self._record(
                        "child-display-name",
                        item_path,
                        "replaced child display name with case-local pseudonym",
                        blocking=False,
                    )
                    self._redactions["display-name"] += 1
                continue

            nested_child = child_context and lower not in {"adult_defendant", "adult_target"}
            output[key] = self._walk(item, path=item_path, inherited_child=nested_child)

        if direct_child:
            output.setdefault("id", pseudonym)
            output.setdefault("display_name", self._display_name(pseudonym))
            output["public_identity_prohibited"] = True
            output["cross_case_linkage_prohibited"] = True
            output.setdefault("age_band", "unknown-child")

        return output

    def _enforce_identity_target(
        self,
        value: Mapping[str, Any],
        *,
        path: str,
        is_child: bool,
    ) -> bool:
        if is_child:
            self._record(
                "named-child-target",
                path,
                "blocked child or minor identity target",
                blocking=True,
            )
            return False

        verified_adult = self._adult_is_verified(value)
        if not verified_adult:
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
        return verified_adult

    def _scan_export(self, value: Any, *, path: str, inherited_child: bool) -> None:
        if isinstance(value, Mapping):
            direct_child = self._is_child(value)
            child_context = inherited_child or direct_child
            identity_target = self._is_identity_target(value)
            verified_adult: bool | None = None
            if identity_target:
                verified_adult = self._enforce_identity_target(
                    value,
                    path=path,
                    is_child=direct_child,
                )

            for key, item in value.items():
                lower = str(key).lower()
                item_path = f"{path}.{key}"
                if identity_target and verified_adult is False and lower in NAME_KEYS:
                    self._record(
                        "export-unverified-target-identifier",
                        item_path,
                        "blocked export containing name without verified adult status",
                        blocking=True,
                    )
                if child_context and lower in CHILD_IDENTIFIER_KEYS:
                    self._record(
                        "export-child-identifier-key",
                        item_path,
                        "blocked export containing child identifier field",
                        blocking=True,
                    )
                if direct_child and lower == "age":
                    self._record(
                        "export-child-exact-age",
                        item_path,
                        "blocked export containing exact child age",
                        blocking=True,
                    )
                if direct_child and lower in {"id", "person_id", "subject_id"}:
                    if not isinstance(item, str) or not self._is_current_case_child_id(item):
                        self._record(
                            "export-cross-case-child-id",
                            item_path,
                            "blocked export containing non-current-case child identifier",
                            blocking=True,
                        )
                nested_child = child_context and lower not in {"adult_defendant", "adult_target"}
                self._scan_export(item, path=item_path, inherited_child=nested_child)
            return

        if isinstance(value, Sequence) and not isinstance(value, (str, bytes)):
            for index, item in enumerate(value):
                self._scan_export(
                    item,
                    path=f"{path}[{index}]",
                    inherited_child=inherited_child,
                )
            return

        if isinstance(value, str) and self._contains_known(value):
            self._record(
                "export-known-child-identifier",
                path,
                "blocked export containing known child identifier",
                blocking=True,
            )

    def _is_child(self, value: Mapping[str, Any]) -> bool:
        if value.get("public_identity_prohibited") is True:
            return True
        if value.get("is_child") is True or value.get("minor") is True:
            return True

        for key in ("age", "age_at_event"):
            age = value.get(key)
            if isinstance(age, (int, float)) and not isinstance(age, bool) and age < 18:
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

        roles: list[str] = []
        for key in ("role", "person_role", "subject_role", "target_role"):
            raw = value.get(key)
            if isinstance(raw, str):
                roles.append(raw.lower())
            elif isinstance(raw, Sequence) and not isinstance(raw, (str, bytes)):
                roles.extend(str(item).lower() for item in raw)
        return any(role in CHILD_ROLES for role in roles)

    @staticmethod
    def _is_identity_target(value: Mapping[str, Any]) -> bool:
        if any(value.get(key) is True for key in IDENTITY_TARGET_KEYS):
            return True
        return str(value.get("target_type", "")).lower() in {
            "named-person",
            "adult-defendant",
            "adult-offender",
        }

    @staticmethod
    def _adult_is_verified(value: Mapping[str, Any]) -> bool:
        age = value.get("age_at_event", value.get("age"))
        adult_status = str(value.get("adult_status", "")).lower()
        return (
            isinstance(age, (int, float))
            and not isinstance(age, bool)
            and age >= 18
        ) or adult_status in {"verified", "authoritative-verified"}

    def _redact_known(self, text: str, *, path: str) -> str:
        result = text
        total = 0
        for identifier in self.known_child_identifiers:
            result, count = re.subn(
                re.escape(identifier),
                REDACTED_CHILD,
                result,
                flags=re.IGNORECASE,
            )
            total += count
        if total:
            self._record(
                "known-child-identifier",
                path,
                "redacted known child identifier",
                blocking=False,
            )
            self._redactions["known-child-identifier"] += total
        return result

    def _contains_known(self, text: str) -> bool:
        folded = text.casefold()
        return any(identifier.casefold() in folded for identifier in self.known_child_identifiers)

    def _record(self, code: str, path: str, action: str, *, blocking: bool) -> None:
        violation = Violation(code=code, path=path, action=action, blocking=blocking)
        if violation not in self._violations:
            self._violations.append(violation)

    def _new_child_id(self) -> str:
        self._child_ordinal += 1
        return f"starintel:child-case-local:{self.case_id}:{self._child_ordinal:02d}"

    def _is_current_case_child_id(self, identifier: str) -> bool:
        prefix = f"starintel:child-case-local:{self.case_id}:"
        suffix = identifier.removeprefix(prefix)
        return identifier.startswith(prefix) and suffix.isdigit() and len(suffix) >= 2

    @staticmethod
    def _display_name(identifier: str | None) -> str:
        ordinal = identifier.rsplit(":", 1)[-1] if identifier else "01"
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
        if not isinstance(case_id, str) or not case_id.strip():
            raise ValueError("case_id is required")
        safe = re.sub(r"[^A-Za-z0-9._:-]+", "-", case_id.strip()).strip("-")
        if not safe:
            raise ValueError("case_id does not contain a usable identifier")
        return safe


def _load_identifiers(path: str | None) -> list[str]:
    if not path:
        return []
    text = Path(path).read_text(encoding="utf-8")
    try:
        payload = json.loads(text)
    except json.JSONDecodeError:
        return [line.strip() for line in text.splitlines() if line.strip()]
    if not isinstance(payload, list) or not all(isinstance(item, str) for item in payload):
        raise ValueError("identifier file must be a JSON string list or one value per line")
    return payload


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
    parser.add_argument("input", help="JSON path or - for stdin")
    parser.add_argument("output", help="JSON path or - for stdout")
    parser.add_argument("--case-id", required=True)
    parser.add_argument("--known-child-identifiers-file")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        firewall = ChildIdentityFirewall(
            case_id=args.case_id,
            known_child_identifiers=_load_identifiers(args.known_child_identifiers_file),
        )
        payload = _read_json(args.input)
        result = firewall.sanitize(payload) if args.command == "sanitize" else firewall.scan_export(payload)
        _write_json(args.output, result.as_dict())
        return 0 if result.allowed else 2
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"child identity firewall failed: {type(error).__name__}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
