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


if __name__ == "__main__":
    unittest.main()
