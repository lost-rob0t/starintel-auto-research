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


LEGACY = """:PROPERTIES:
:ID:       unreachable-base-test
:END:
#+title: Unreachable base test
#+description: Legacy research fixture.
#+status: REVIEW
#+filetags: :starintel:research:test:

* Findings

The body must survive canonical migration unchanged.
"""


def canonical(*, base_commit: str, base_blob: str) -> str:
    return f""":PROPERTIES:
:ID:       unreachable-base-test
:END:
#+title: Unreachable base test
#+description: Legacy research fixture.
#+status: REVIEW
#+approval_schema: adard.research-approval.v1
#+approval_state: PENDING
#+approval_actor: research-approval-migration
#+approval_evidence: fixture migration
#+approval_base_commit: {base_commit}
#+approval_base_blob: {base_blob}
#+approval_decided_at: NONE
#+filetags: :starintel:research:test:

* Findings

The body must survive canonical migration unchanged.
"""


class UnreachableApprovalBaseTests(unittest.TestCase):
    def git(self, root: Path, *args: str, check: bool = True) -> str:
        return subprocess.run(
            ["git", *args],
            cwd=root,
            text=True,
            capture_output=True,
            check=check,
        ).stdout.strip()

    def setup_repo(self) -> tuple[Path, tempfile.TemporaryDirectory[str], Path]:
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        self.git(root, "init", "-b", "main")
        self.git(root, "config", "user.name", "Test")
        self.git(root, "config", "user.email", "test@example.invalid")
        path = root / "roam" / "research" / "test" / "record.org"
        path.parent.mkdir(parents=True)
        return root, temporary, path

    def test_unreachable_commit_recovers_exact_blob_from_head_ancestry(self) -> None:
        root, temporary, path = self.setup_repo()
        with temporary:
            path.write_text(LEGACY, encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "legacy research")
            base_blob = self.git(root, "rev-parse", f"HEAD:{path.relative_to(root).as_posix()}")
            unreachable = "54dbb10a30727a6dc9893d3b735205df7dd4141a3"

            path.write_text(
                canonical(base_commit=unreachable, base_blob=base_blob),
                encoding="utf-8",
            )
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "canonicalize with stale orphan anchor")

            self.assertEqual(verify_repository(root), 1)

    def test_unreachable_commit_recovery_fails_on_duplicate_blob_paths(self) -> None:
        root, temporary, path = self.setup_repo()
        with temporary:
            other = path.with_name("duplicate.org")
            path.write_text(LEGACY, encoding="utf-8")
            other.write_text(LEGACY, encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "duplicate legacy research")
            base_blob = self.git(root, "rev-parse", f"HEAD:{path.relative_to(root).as_posix()}")
            unreachable = "54dbb10a30727a6dc9893d3b735205df7dd4141a3"

            other.unlink()
            path.write_text(
                canonical(base_commit=unreachable, base_blob=base_blob),
                encoding="utf-8",
            )
            self.git(root, "add", "-A")
            self.git(root, "commit", "-m", "canonicalize one duplicate")

            with self.assertRaisesRegex(MigrationError, "ambiguous"):
                verify_repository(root)


if __name__ == "__main__":
    unittest.main()
