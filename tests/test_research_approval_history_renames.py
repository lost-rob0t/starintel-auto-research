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
:ID:       rename-test
:END:
#+title: OLD-001 Rename Test
#+description: Approval migration rename fixture.
#+status: DONE
#+filetags: :starintel:research:test:

* Findings

The research body is stable across migration.
"""


def canonical(*, base_commit: str, base_blob: str, title: str = "OLD-001 Rename Test") -> str:
    return f""":PROPERTIES:
:ID:       rename-test
:END:
#+title: {title}
#+description: Approval migration rename fixture.
#+status: DONE
#+approval_schema: adard.research-approval.v1
#+approval_state: APPROVED
#+approval_actor: operator
#+approval_evidence: fixture approval
#+approval_base_commit: {base_commit}
#+approval_base_blob: {base_blob}
#+approval_decided_at: 2026-01-01
#+filetags: :starintel:research:test:

* Findings

The research body is stable across migration.
"""


class ApprovalHistoryRenameTests(unittest.TestCase):
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
        return root, temporary

    def test_exact_base_blob_follows_unique_later_rename(self) -> None:
        root, temporary = self.setup_repo()
        with temporary:
            old_path = root / "roam" / "research" / "test" / "OLD-001.org"
            old_path.parent.mkdir(parents=True)
            old_path.write_text(LEGACY, encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "legacy research")
            base_commit = self.git(root, "rev-parse", "HEAD")
            base_blob = self.git(root, "rev-parse", f"HEAD:{old_path.relative_to(root).as_posix()}")

            old_path.write_text(
                canonical(base_commit=base_commit, base_blob=base_blob),
                encoding="utf-8",
            )
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "canonicalize approval")

            new_path = old_path.with_name("NEW-001.org")
            self.git(root, "mv", old_path.relative_to(root).as_posix(), new_path.relative_to(root).as_posix())
            new_path.write_text(
                canonical(
                    base_commit=base_commit,
                    base_blob=base_blob,
                    title="NEW-001 Rename Test",
                ),
                encoding="utf-8",
            )
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "rename canonical document")

            self.assertEqual(verify_repository(root), 1)

    def test_ambiguous_base_blob_does_not_guess_historical_path(self) -> None:
        root, temporary = self.setup_repo()
        with temporary:
            directory = root / "roam" / "research" / "test"
            directory.mkdir(parents=True)
            first = directory / "OLD-A.org"
            second = directory / "OLD-B.org"
            first.write_text(LEGACY, encoding="utf-8")
            second.write_text(LEGACY, encoding="utf-8")
            self.git(root, "add", ".")
            self.git(root, "commit", "-m", "duplicate legacy blobs")
            base_commit = self.git(root, "rev-parse", "HEAD")
            base_blob = self.git(root, "rev-parse", f"HEAD:{first.relative_to(root).as_posix()}")

            first.unlink()
            second.unlink()
            current = directory / "NEW-001.org"
            current.write_text(
                canonical(base_commit=base_commit, base_blob=base_blob),
                encoding="utf-8",
            )
            self.git(root, "add", "-A")
            self.git(root, "commit", "-m", "replace ambiguous legacy paths")

            with self.assertRaisesRegex(MigrationError, "approval base blob .* is ambiguous"):
                verify_repository(root)


if __name__ == "__main__":
    unittest.main()
