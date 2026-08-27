from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from research_approval_migration import (
    CANONICAL_SCHEMA,
    MigrationError,
    discover_research_files,
    migrate_document,
)


def document(
    *,
    status: str = "REVIEW",
    body: str = "* Findings\n\nThe research body.\n",
    approval: str = "",
) -> str:
    return (
        ":PROPERTIES:\n"
        ":ID:       test-research\n"
        ":END:\n"
        "#+title: Test research\n"
        "#+description: A test research record.\n"
        f"#+status: {status}\n"
        "#+filetags: :starintel:research:test:\n"
        f"{approval}"
        "\n"
        f"{body}"
    )


def approval_table(row: str) -> str:
    return (
        "* Approval Table\n"
        "\n"
        "| Approval area | Required authority | State | Evidence required | Evidence reference |\n"
        "|---------------+--------------------+-------+-------------------+--------------------|\n"
        f"{row}\n"
    )


class ResearchApprovalMigrationTests(unittest.TestCase):
    def migrate(self, text: str, path: str = "research/test.org"):
        return migrate_document(
            text,
            relative_path=Path(path),
            base_commit="0123456789abcdef0123456789abcdef01234567",
            base_blob="fedcba9876543210fedcba9876543210fedcba98",
        )

    def test_review_awaiting_operator_maps_to_pending(self) -> None:
        result = self.migrate(document(status="REVIEW"))
        self.assertEqual(result.approval_state, "PENDING")
        self.assertIn("#+approval_state: PENDING\n", result.text)
        self.assertIn("no explicit human research-conclusion decision", result.approval_evidence)

    def test_researched_awaiting_operator_maps_to_pending(self) -> None:
        result = self.migrate(document(status="RESEARCHED"))
        self.assertEqual(result.approval_state, "PENDING")

    def test_verified_awaiting_operator_maps_to_pending(self) -> None:
        result = self.migrate(document(status="VERIFIED"))
        self.assertEqual(result.approval_state, "PENDING")

    def test_explicit_old_human_approval_maps_to_approved(self) -> None:
        old_table = (
            "| Version | Date | Description | Did nsaspy approve it |\n"
            "|---------+------+-------------+-----------------------|\n"
            "| 1.0.0 | 2026-08-12 | Approve this research conclusion | Yes |\n"
        )
        result = self.migrate(document(approval=old_table))
        self.assertEqual(result.approval_state, "APPROVED")
        self.assertEqual(result.approval_actor, "nsaspy")
        self.assertEqual(result.approval_decided_at, "2026-08-12")

    def test_explicit_rejection_maps_to_rejected(self) -> None:
        result = self.migrate(
            document(
                approval=approval_table(
                    "| Research conclusion | StarIntel operator | REJECTED | Explicit rejection | issue #9 |"
                )
            )
        )
        self.assertEqual(result.approval_state, "REJECTED")
        self.assertEqual(result.approval_actor, "operator")

    def test_publication_pending_does_not_override_approved_research(self) -> None:
        result = self.migrate(
            document(
                approval=approval_table(
                    "| Research basis | Research reviewer | APPROVED | Human review | operator decision 2026-08-12 |\n"
                    "| Publication | Maintainer | PENDING | Pages build | |"
                )
            )
        )
        self.assertEqual(result.approval_state, "APPROVED")

    def test_design_promotion_approval_does_not_become_research_approval(self) -> None:
        result = self.migrate(
            document(
                approval=approval_table(
                    "| Architecture design | StarIntel operator | APPROVED | Design review | operator decision 2026-08-12 |"
                )
            )
        )
        self.assertEqual(result.approval_state, "PENDING")

    def test_done_lifecycle_remains_done(self) -> None:
        result = self.migrate(document(status="DONE"))
        self.assertIn("#+status: DONE\n", result.text)
        self.assertEqual(result.lifecycle, "DONE")

    def test_only_header_changes_and_body_is_preserved(self) -> None:
        body = "* Findings\n\nA | literal\n#+begin_example\n* not a heading\n#+end_example\n"
        original = document(body=body)
        result = self.migrate(original)
        self.assertEqual(result.body, body)
        self.assertEqual(result.text.split("* Findings\n", 1)[1], body.split("* Findings\n", 1)[1])
        self.assertIn(f"#+approval_schema: {CANONICAL_SCHEMA}\n", result.text)
        self.assertLess(result.text.index("#+status:"), result.text.index("#+approval_schema:"))
        self.assertIn("#+approval_base_commit: 0123456789abcdef0123456789abcdef01234567\n", result.text)
        self.assertIn("#+approval_base_blob: fedcba9876543210fedcba9876543210fedcba98\n", result.text)

    def test_second_migration_is_idempotent(self) -> None:
        first = self.migrate(document())
        second = self.migrate(
            first.text,
            path="research/test.org",
        )
        self.assertEqual(first.text, second.text)
        self.assertFalse(second.changed)

    def test_contradictory_research_approval_fails_closed(self) -> None:
        with self.assertRaises(MigrationError):
            self.migrate(
                document(
                    approval=approval_table(
                        "| Research conclusion | Operator | APPROVED | approval | operator 2026-08-12 |\n"
                        "| Research conclusion | Operator | REJECTED | rejection | operator 2026-08-13 |"
                    )
                )
            )

    def test_discovery_is_limited_to_research_tree(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            research = root / "roam" / "research" / "star-server" / "record.org"
            design = root / "roam" / "design" / "star-server" / "design.org"
            research.parent.mkdir(parents=True)
            design.parent.mkdir(parents=True)
            research.write_text(document(), encoding="utf-8")
            design.write_text(document(), encoding="utf-8")
            self.assertEqual(discover_research_files(root), [research])


if __name__ == "__main__":
    unittest.main()
