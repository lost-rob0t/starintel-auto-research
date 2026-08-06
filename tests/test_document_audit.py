from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
VALIDATOR = ROOT / "scripts" / "validate-docs.py"

APPROVAL = """* Approval Table

| Approval area | Required authority | State | Evidence required | Evidence reference |
|---------------+--------------------+-------+-------------------+--------------------|
| Research basis | Research reviewer | PENDING | Current source review | |
"""

CHANGELOG = """* Changelog

| Date | Change | Author or actor | Evidence |
|------+--------+-----------------+----------|
| 2026-08-06 | Created test document | test suite | fixture |
"""


class DocumentAuditTests(unittest.TestCase):
    def make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for tree in ("design", "research", "implement", "indexes"):
            (root / "roam" / tree / "test").mkdir(parents=True)
        (root / "roam" / ".implemented").touch()
        (root / "roam" / ".rejected").touch()
        (root / ".github" / "workflows").mkdir(parents=True)
        shutil.copy2(ROOT / "AGENTS.md", root / "AGENTS.md")
        shutil.copy2(
            ROOT / ".github" / "workflows" / "pages.yml",
            root / ".github" / "workflows" / "pages.yml",
        )
        return root

    def write_doc(
        self,
        root: Path,
        name: str,
        *,
        identifier: str | None = None,
        approval: str = APPROVAL,
        changelog: str = CHANGELOG,
        body: str = "* Findings\n\nVerified test finding.\n",
    ) -> Path:
        identifier = identifier or f"test-{Path(name).stem.lower()}"
        path = root / "roam" / "research" / "test" / name
        path.write_text(
            ":PROPERTIES:\n"
            f":ID:       {identifier}\n"
            ":END:\n"
            f"#+title: {Path(name).stem}\n"
            "#+description: Test repository document.\n"
            "#+status: DRAFT\n"
            "#+filetags: :starintel:research:test:\n\n"
            f"{approval}\n{body}\n{changelog}",
            encoding="utf-8",
        )
        return path

    def run_validator(
        self, root: Path, *arguments: str
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [
                sys.executable,
                str(VALIDATOR),
                "--root",
                str(root),
                *arguments,
            ],
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_valid_document_passes(self) -> None:
        root = self.make_repo()
        self.write_doc(root, "VALID.org")
        result = self.run_validator(root)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("repository document audit passed", result.stdout)

    def test_missing_approval_reports_actionable_context(self) -> None:
        root = self.make_repo()
        path = self.write_doc(root, "MISSING-APPROVAL.org", approval="")
        result = self.run_validator(root)
        self.assertEqual(result.returncode, 1)
        output = result.stdout + result.stderr
        self.assertIn(str(path.relative_to(root)), output)
        self.assertIn("rule=missing-approval-table", output)
        self.assertIn("class=research", output)
        self.assertIn("correction=add the canonical five-column Approval Table", output)

    def test_fixer_adds_pending_approval_without_fabricating_approval(self) -> None:
        root = self.make_repo()
        path = self.write_doc(root, "FIX.org", approval="", changelog="")
        fixed = self.run_validator(
            root,
            "--fix",
            "--audit-date",
            "2026-08-06",
            "--actor",
            "test audit",
        )
        self.assertEqual(fixed.returncode, 0, fixed.stdout + fixed.stderr)
        text = path.read_text(encoding="utf-8")
        self.assertIn("* Approval Table", text)
        self.assertIn("| Research basis | Research reviewer | PENDING |", text)
        self.assertNotIn("| APPROVED |", text)
        self.assertIn("* Changelog", text)
        self.assertIn("| 2026-08-06 |", text)

    def test_duplicate_ids_fail(self) -> None:
        root = self.make_repo()
        self.write_doc(root, "ONE.org", identifier="duplicate-test-id")
        self.write_doc(root, "TWO.org", identifier="duplicate-test-id")
        result = self.run_validator(root)
        self.assertEqual(result.returncode, 1)
        self.assertIn("rule=duplicate-id:duplicate-test-id", result.stderr)

    def test_approved_row_requires_evidence_reference(self) -> None:
        root = self.make_repo()
        approval = APPROVAL.replace("PENDING", "APPROVED")
        self.write_doc(root, "UNSUPPORTED-APPROVAL.org", approval=approval)
        result = self.run_validator(root)
        self.assertEqual(result.returncode, 1)
        self.assertIn("approved-without-evidence", result.stderr)

    def test_unresolved_org_id_fails(self) -> None:
        root = self.make_repo()
        self.write_doc(
            root,
            "BROKEN-LINK.org",
            body="* Findings\n\nSee [[id:does-not-exist][missing node]].\n",
        )
        result = self.run_validator(root)
        self.assertEqual(result.returncode, 1)
        self.assertIn("unresolved-id-link:does-not-exist", result.stderr)


if __name__ == "__main__":
    unittest.main()
