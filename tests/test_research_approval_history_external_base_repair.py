from __future__ import annotations

import subprocess
import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

from research_approval_migration import MigrationError
from verify_research_approval_history import verify_repository


def canonical_record(*, base_commit: str) -> str:
    return f""":PROPERTIES:
:ID:       external-base-repair
:END:
#+title: External base repair
#+description: Canonical-born provenance repair test.
#+status: READY_FOR_DESIGN
#+approval_schema: adard.research-approval.v1
#+approval_state: PENDING
#+approval_actor: research-worker
#+approval_evidence: test record
#+approval_base_commit: {base_commit}
#+approval_base_blob: NONE
#+approval_decided_at: NONE
#+filetags: :starintel:research:test:

* Findings

Body remains unchanged.
"""


class ExternalApprovalBaseRepairTests(unittest.TestCase):
    def git(self, root: Path, *args: str, check: bool = True) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=root,
            text=True,
            capture_output=True,
            check=check,
        ).stdout.strip()

    def setup_repo(self) -> tuple[Path, tempfile.TemporaryDirectory[str], Path, str]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        self.git(root, "init", "-b", "main")
        self.git(root, "config", "user.name", "Test")
        self.git(root, "config", "user.email", "test@example.invalid")
        (root / "README").write_text("baseline\n", encoding="utf-8")
        self.git(root, "add", ".")
        self.git(root, "commit", "-m", "seed repository")
        parent = self.git(root, "rev-parse", "HEAD")
        path = root / "roam" / "research" / "test" / "record.org"
        path.parent.mkdir(parents=True)
        return root, temporary, path, parent

    def test_foreign_base_can_be_repaired_to_creation_parent(self) -> None:
        root, temporary, path, parent = self.setup_repo()
        with temporary:
            foreign = "8fb297d146e7332fae7e38170b5b49d49530ac53"
            path.write_text(canonical_record(base_commit=foreign), encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "create record with foreign provenance")

            path.write_text(canonical_record(base_commit=parent), encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "repair provenance to creation parent")

            self.assertEqual(verify_repository(root), 1)

    def test_foreign_base_cannot_be_repaired_to_non_parent(self) -> None:
        root, temporary, path, parent = self.setup_repo()
        with temporary:
            self.git(root, "commit", "--allow-empty", "-m", "unrelated later anchor")
            non_parent = self.git(root, "rev-parse", "HEAD")
            foreign = "8fb297d146e7332fae7e38170b5b49d49530ac53"
            path.write_text(canonical_record(base_commit=foreign), encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "create record with foreign provenance")

            path.write_text(canonical_record(base_commit=parent), encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "attempt wrong provenance repair")

            with self.assertRaisesRegex(MigrationError, "corrected approval base must be a parent"):
                verify_repository(root)


if __name__ == "__main__":
    unittest.main()
