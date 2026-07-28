from __future__ import annotations

import importlib.util
import json
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "child_identity_firewall.py"
SPEC = importlib.util.spec_from_file_location("child_identity_firewall", MODULE_PATH)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = MODULE
SPEC.loader.exec_module(MODULE)

ChildIdentityFirewall = MODULE.ChildIdentityFirewall
REDACTED_CHILD = MODULE.REDACTED_CHILD
REJECTED_QUERY = MODULE.REJECTED_QUERY


class ChildIdentityFirewallTests(unittest.TestCase):
    def firewall(self) -> ChildIdentityFirewall:
        return ChildIdentityFirewall(
            case_id="synthetic-case-001",
            known_child_identifiers=["Synthetic Minor Alpha", "S.M.A."],
        )

    def test_child_entity_is_pseudonymized_and_minimized(self) -> None:
        payload = {
            "role": "child-victim",
            "name": "Synthetic Minor Alpha",
            "age": 7,
            "school_name": "Synthetic School",
            "evidence": {
                "text": "Synthetic Minor Alpha was identified in the source.",
                "url": "https://example.invalid/Synthetic-Minor-Alpha/case",
            },
        }

        result = self.firewall().sanitize(payload)

        self.assertTrue(result.allowed)
        self.assertNotIn("name", result.sanitized)
        self.assertNotIn("school_name", result.sanitized)
        self.assertNotIn("age", result.sanitized)
        self.assertEqual(result.sanitized["age_band"], "5-9")
        self.assertEqual(result.sanitized["display_name"], "Child victim 01")
        self.assertEqual(
            result.sanitized["id"],
            "starintel:child-case-local:synthetic-case-001:01",
        )
        self.assertEqual(
            result.sanitized["evidence"]["text"],
            f"{REDACTED_CHILD} was identified in the source.",
        )
        self.assertIn(REDACTED_CHILD, result.sanitized["evidence"]["url"])
        self.assertNotIn("Synthetic Minor Alpha", json.dumps(result.as_dict()))

    def test_known_child_identifier_in_query_fails_closed(self) -> None:
        result = self.firewall().sanitize(
            {"search_query": "Synthetic Minor Alpha parents and school"}
        )

        self.assertFalse(result.allowed)
        self.assertEqual(result.sanitized["search_query"], REJECTED_QUERY)
        self.assertIn("unsafe-child-query", {item.code for item in result.violations})
        self.assertNotIn("Synthetic Minor Alpha", json.dumps(result.as_dict()))

    def test_explicit_child_name_query_field_fails_closed(self) -> None:
        result = self.firewall().sanitize(
            {"child_name": "Synthetic Minor Alpha", "query": "county fatality charged"}
        )

        self.assertFalse(result.allowed)
        self.assertNotIn("child_name", result.sanitized)
        self.assertIn("child-query-field", {item.code for item in result.violations})

    def test_unknown_age_named_target_is_blocked_and_name_removed(self) -> None:
        result = self.firewall().sanitize(
            {
                "identity_target": True,
                "target_type": "adult-defendant",
                "name": "Synthetic Unknown Person",
                "legal_status": "charged",
            }
        )

        self.assertFalse(result.allowed)
        self.assertNotIn("name", result.sanitized)
        self.assertIn("adult-status-unverified", {item.code for item in result.violations})
        self.assertIn("unverified-target-identifier", {item.code for item in result.violations})

    def test_verified_adult_charged_target_is_allowed(self) -> None:
        payload = {
            "identity_target": True,
            "target_type": "adult-defendant",
            "name": "Synthetic Adult Defendant",
            "age_at_event": 31,
            "legal_status": "charged",
        }

        result = self.firewall().sanitize(payload)

        self.assertTrue(result.allowed)
        self.assertEqual(result.sanitized["name"], "Synthetic Adult Defendant")

    def test_minor_alleged_offender_is_unnamed_and_blocked(self) -> None:
        result = self.firewall().sanitize(
            {
                "identity_target": True,
                "target_type": "named-person",
                "role": "minor",
                "name": "Synthetic Minor Defendant",
                "age_at_event": 16,
                "legal_status": "charged",
            }
        )

        self.assertFalse(result.allowed)
        self.assertNotIn("name", result.sanitized)
        self.assertIn("named-child-target", {item.code for item in result.violations})

    def test_cross_case_child_identifier_is_replaced_and_blocks(self) -> None:
        result = self.firewall().sanitize(
            {
                "role": "child-victim",
                "id": "starintel:child-case-local:another-case:01",
                "age_band": "1-4",
            }
        )

        self.assertFalse(result.allowed)
        self.assertEqual(
            result.sanitized["id"],
            "starintel:child-case-local:synthetic-case-001:01",
        )
        self.assertIn("cross-case-child-id", {item.code for item in result.violations})

    def test_current_case_child_identifier_is_preserved(self) -> None:
        identifier = "starintel:child-case-local:synthetic-case-001:09"
        result = self.firewall().sanitize(
            {"role": "child-victim", "id": identifier, "age_band": "10-13"}
        )

        self.assertTrue(result.allowed)
        self.assertEqual(result.sanitized["id"], identifier)
        self.assertEqual(result.sanitized["display_name"], "Child victim 09")

    def test_export_scanner_detects_nested_known_identifier(self) -> None:
        export = {
            "child": {
                "role": "child-victim",
                "id": "starintel:child-case-local:synthetic-case-001:01",
                "display_name": "Child victim 01",
                "age_band": "5-9",
                "evidence": {"text": "Synthetic Minor Alpha appears here."},
            }
        }

        result = self.firewall().scan_export(export)

        self.assertFalse(result.allowed)
        self.assertIn(
            "export-known-child-identifier",
            {item.code for item in result.violations},
        )

    def test_export_scanner_blocks_unverified_named_target(self) -> None:
        export = {
            "identity_target": True,
            "target_type": "adult-defendant",
            "name": "Synthetic Unknown Person",
            "legal_status": "charged",
        }

        result = self.firewall().scan_export(export)

        self.assertFalse(result.allowed)
        self.assertIn(
            "export-unverified-target-identifier",
            {item.code for item in result.violations},
        )

    def test_safe_export_passes(self) -> None:
        export = {
            "child": {
                "role": "child-victim",
                "id": "starintel:child-case-local:synthetic-case-001:01",
                "display_name": "Child victim 01",
                "age_band": "5-9",
                "public_identity_prohibited": True,
                "cross_case_linkage_prohibited": True,
                "evidence": {"text": "[CHILD] appears in the redacted source."},
            },
            "adult_defendant": {
                "name": "Synthetic Adult Defendant",
                "age_at_event": 31,
                "legal_status": "charged",
            },
        }

        self.assertTrue(self.firewall().scan_export(export).allowed)

    def test_source_has_no_network_or_autodig_dependency(self) -> None:
        source = MODULE_PATH.read_text(encoding="utf-8").lower()
        prohibited = (
            "import requests",
            "import urllib",
            "import socket",
            "http.client",
            "subprocess",
            "autodig",
            "auto-dig",
        )
        for token in prohibited:
            self.assertNotIn(token, source)


if __name__ == "__main__":
    unittest.main()
