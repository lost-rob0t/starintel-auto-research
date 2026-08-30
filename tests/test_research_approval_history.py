from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from research_approval_migration import MigrationError, migrate_document
from verify_research_approval_history import verify_repository


LEGACY = """:PROPERTIES:
:ID:       history-test
:END:
#+title: History test
#+description: Approval migration history test.
#+status: REVIEW
#+filetags: :starintel:research:test:

* Findings

Original research body.
"""


def canonical_record(*, base_commit: str, base_blob: str) -> str:
    return f""":PROPERTIES:
:ID:       history-test
:END:
#+title: History test
#+description: Approval migration history test.
#+status: RESEARCHING
#+approval_schema: adard.research-approval.v1
#+approval_state: PENDING
#+approval_actor: research-worker
#+approval_evidence: canonical-born research requires human approval
#+approval_base_commit: {base_commit}
#+approval_base_blob: {base_blob}
#+approval_decided_at: NONE
#+filetags: :starintel:research:test:

* Findings

Canonical-born research body.
"""


class ResearchApprovalHistoryTests(unittest.TestCase):
    def git(self, root: Path, *args: str) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=root,
            text=True,
            capture_output=True,
            check=True,
        ).stdout.strip()

    def setup_repo(self) -> tuple[Path, tempfile.TemporaryDirectory[str]]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        self.git(root, "init", "-b", "main")
        self.git(root, "config", "user.name", "Test")
        self.git(root, "config", "user.email", "test@example.invalid")
        path = root / "roam" / "research" / "test" / "record.org"
        path.parent.mkdir(parents=True)
        path.write_text(LEGACY, encoding="utf-8")
        self.git(root, "add", ".")
        self.git(root, "commit", "-m", "seed research")
        return root, temporary

    def setup_empty_repo(self) -> tuple[Path, tempfile.TemporaryDirectory[str]]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        self.git(root, "init", "-b", "main")
        self.git(root, "config", "user.name", "Test")
        self.git(root, "config", "user.email", "test@example.invalid")
        (root / "README").write_text("baseline\n", encoding="utf-8")
        self.git(root, "add", ".")
        self.git(root, "commit", "-m", "seed repository")
        return root, temporary

    def migrate(self, root: Path, *, change_body_before_commit: bool = False) -> Path:
        path = root / "roam" / "research" / "test" / "record.org"
        base_commit = self.git(root, "rev-parse", "HEAD")
        base_blob = self.git(root, "hash-object", str(path))
        migrated = migrate_document(
            path.read_text(encoding="utf-8"),
            relative_path=path.relative_to(root),
            base_commit=base_commit,
            base_blob=base_blob,
        ).text
        if change_body_before_commit:
            migrated = migrated.replace("Original research body.", "Changed during migration.")
        path.write_text(migrated, encoding="utf-8")
        self.git(root, "add", ".")
        self.git(root, "commit", "-m", "migrate approval metadata")
        return path

    def test_later_research_body_edit_is_allowed(self) -> None:
        root, temporary = self.setup_repo()
        with temporary:
            path = self.migrate(root)
            text = path.read_text(encoding="utf-8").replace(
                "Original research body.", "Legitimate later research edit."
            )
            path.write_text(text, encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "expand research")
            self.assertEqual(verify_repository(root), 1)

    def test_body_change_in_first_canonical_commit_still_fails(self) -> None:
        root, temporary = self.setup_repo()
        with temporary:
            self.migrate(root, change_body_before_commit=True)
            with self.assertRaisesRegex(MigrationError, "research body changed during migration"):
                verify_repository(root)

    def test_legacy_approval_schema_before_adard_migration_is_ignored(self) -> None:
        root, temporary = self.setup_repo()
        with temporary:
            path = root / "roam" / "research" / "test" / "record.org"
            old_schema = LEGACY.replace(
                "#+status: REVIEW\n",
                "#+status: REVIEW\n"
                "#+approval_schema: prolog-rlm.research-approval.v1\n"
                "#+approval_state: PENDING\n"
                "#+approval_actor: legacy-migration\n"
                "#+approval_evidence: legacy metadata\n"
                "#+approval_base_commit: legacy\n"
                "#+approval_base_blob: legacy\n"
                "#+approval_decided_at: NONE\n",
            )
            path.write_text(old_schema, encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "legacy approval namespace")
            base_commit = self.git(root, "rev-parse", "HEAD")
            base_blob = self.git(root, "hash-object", str(path))

            adard = old_schema.replace(
                "#+approval_schema: prolog-rlm.research-approval.v1\n"
                "#+approval_state: PENDING\n"
                "#+approval_actor: legacy-migration\n"
                "#+approval_evidence: legacy metadata\n"
                "#+approval_base_commit: legacy\n"
                "#+approval_base_blob: legacy\n"
                "#+approval_decided_at: NONE\n",
                "#+approval_schema: adard.research-approval.v1\n"
                "#+approval_state: PENDING\n"
                "#+approval_actor: research-approval-migration\n"
                "#+approval_evidence: namespace migration\n"
                f"#+approval_base_commit: {base_commit}\n"
                f"#+approval_base_blob: {base_blob}\n"
                "#+approval_decided_at: NONE\n",
            )
            path.write_text(adard, encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "migrate to adard approval namespace")
            self.assertEqual(verify_repository(root), 1)

    def test_partial_canonical_base_can_be_repaired_when_exactly_anchored(self) -> None:
        root, temporary = self.setup_repo()
        with temporary:
            path = root / "roam" / "research" / "test" / "record.org"
            partial = LEGACY.replace(
                "#+status: REVIEW\n",
                "#+status: REVIEW\n"
                "#+approval_schema: adard.research-approval.v1\n"
                "#+approval_state: PENDING\n"
                "#+approval_actor: legacy-partial-writer\n"
                "#+approval_evidence: partial migration awaiting provenance\n",
            )
            path.write_text(partial, encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "write partial canonical approval metadata")
            base_commit = self.git(root, "rev-parse", "HEAD")
            base_blob = self.git(root, "hash-object", str(path))

            repaired = partial.replace(
                "#+approval_evidence: partial migration awaiting provenance\n",
                "#+approval_evidence: partial migration awaiting provenance\n"
                f"#+approval_base_commit: {base_commit}\n"
                f"#+approval_base_blob: {base_blob}\n"
                "#+approval_decided_at: NONE\n",
            )
            path.write_text(repaired, encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "repair partial approval provenance")

            self.assertEqual(verify_repository(root), 1)

    def test_canonical_born_record_with_none_provenance_is_allowed(self) -> None:
        root, temporary = self.setup_empty_repo()
        with temporary:
            path = root / "roam" / "research" / "test" / "record.org"
            path.parent.mkdir(parents=True)
            path.write_text(
                canonical_record(base_commit="NONE", base_blob="NONE"),
                encoding="utf-8",
            )
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "create canonical research")
            self.assertEqual(verify_repository(root), 1)

    def test_backfilled_record_can_anchor_absence_at_base_commit(self) -> None:
        root, temporary = self.setup_empty_repo()
        with temporary:
            base_commit = self.git(root, "rev-parse", "HEAD")
            path = root / "roam" / "research" / "test" / "record.org"
            path.parent.mkdir(parents=True)
            path.write_text(
                canonical_record(base_commit=base_commit, base_blob="NONE"),
                encoding="utf-8",
            )
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "backfill canonical research")
            self.assertEqual(verify_repository(root), 1)

    def test_none_blob_is_rejected_when_path_existed_at_base(self) -> None:
        root, temporary = self.setup_repo()
        with temporary:
            path = root / "roam" / "research" / "test" / "record.org"
            base_commit = self.git(root, "rev-parse", "HEAD")
            path.write_text(
                canonical_record(base_commit=base_commit, base_blob="NONE"),
                encoding="utf-8",
            )
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "claim absent base")
            with self.assertRaisesRegex(MigrationError, "NONE but path exists at base"):
                verify_repository(root)


if __name__ == "__main__":
    unittest.main()
