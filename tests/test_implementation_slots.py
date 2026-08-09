from __future__ import annotations

import datetime as dt
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"


class ImplementationSlotTests(unittest.TestCase):
    def make_repo(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        for tree in ("design", "research", "implement", "indexes"):
            (root / "roam" / tree).mkdir(parents=True)
        (root / "roam" / ".implemented").touch()
        (root / "roam" / ".rejected").touch()
        (root / "scripts").mkdir()
        (root / ".github" / "workflows").mkdir(parents=True)
        shutil.copy2(ROOT / "AGENTS.md", root / "AGENTS.md")
        shutil.copy2(SCRIPTS / "validate-docs.py", root / "scripts" / "validate-docs.py")
        shutil.copy2(
            ROOT / ".github" / "workflows" / "pages.yml",
            root / ".github" / "workflows" / "pages.yml",
        )
        return root

    def add_project(self, root: Path, project: str) -> None:
        for tree in ("design", "research", "implement", "indexes"):
            (root / "roam" / tree / project).mkdir(exist_ok=True)

    def design_text(self, project: str, name: str, *, active: bool = False) -> str:
        stem = Path(name).stem.lower().replace("_", "-")
        suffix = "-implementation" if active else ""
        identifier = f"test-{project}-{stem}{suffix}"
        title_suffix = " — Active Implementation" if active else ""
        status = "IMPLEMENTING" if active else "REVIEW"
        tags = ":starintel:implementation:" if active else ":starintel:design:"
        canonical = (
            f"#+canonical_id: test-{project}-{stem}\n" if active else ""
        )
        canonical_section = (
            "* Canonical Design\n\n"
            f"- [[id:test-{project}-{stem}][Canonical design]]\n\n"
            if active
            else ""
        )
        today = dt.date.today().isoformat()
        return (
            ":PROPERTIES:\n"
            f":ID:       {identifier}\n"
            ":END:\n"
            f"#+title: {name}{title_suffix}\n"
            "#+description: Test design for the implementation-slot workflow.\n"
            f"#+status: {status}\n"
            f"#+filetags: {tags}\n"
            f"{canonical}"
            "\n"
            f"{canonical_section}"
            "* Approval Table\n\n"
            "| Approval area | Required authority | State | Evidence required | Evidence reference |\n"
            "|---------------+--------------------+-------+-------------------+--------------------|\n"
            "| Implementation | Test maintainer | PENDING | Test review | |\n\n"
            "* Changelog\n\n"
            "| Date | Change | Author or actor | Evidence |\n"
            "|------+--------+-----------------+----------|\n"
            f"| {today} | Created test document | test suite | fixture |\n"
        )

    def add_design(
        self, root: Path, project: str, name: str, active: bool = False
    ) -> Path:
        self.add_project(root, project)
        canonical = root / "roam" / "design" / project / name
        canonical.write_text(self.design_text(project, name), encoding="utf-8")
        if active:
            (root / "roam" / "implement" / project / name).write_text(
                self.design_text(project, name, active=True), encoding="utf-8"
            )
        return canonical

    def run_script(
        self, root: Path, script: str, *args: str
    ) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPTS / script), *args],
            cwd=root,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_independent_projects_may_each_have_one_active_design(self) -> None:
        root = self.make_repo()
        self.add_design(root, "star-lang", "STAR-LANG-001.org", active=True)
        self.add_design(root, "quasar", "QUASAR-002.org", active=True)
        result = self.run_script(root, "sync.py", "--check")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_same_project_still_rejects_two_active_designs(self) -> None:
        root = self.make_repo()
        self.add_design(root, "star-lang", "STAR-LANG-001.org", active=True)
        self.add_design(root, "star-lang", "STAR-LANG-002.org", active=True)
        result = self.run_script(root, "sync.py", "--check")
        self.assertEqual(result.returncode, 2)
        self.assertIn(
            "implementation slot for project star-lang contains 2 Org files",
            result.stdout + result.stderr,
        )

    def test_implement_selects_an_empty_project_slot(self) -> None:
        root = self.make_repo()
        self.add_design(root, "star-lang", "STAR-LANG-001.org", active=True)
        design = self.add_design(root, "quasar", "QUASAR-002.org")
        result = self.run_script(root, "implement.py", str(design.relative_to(root)))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        active = root / "roam" / "implement" / "quasar" / "QUASAR-002.org"
        self.assertTrue(active.is_file())
        active_text = active.read_text(encoding="utf-8")
        canonical_text = design.read_text(encoding="utf-8")
        self.assertIn("#+status: IMPLEMENTING", active_text)
        self.assertIn("* Canonical Design", active_text)
        self.assertNotEqual(
            self.file_id(canonical_text),
            self.file_id(active_text),
        )

    def test_implement_rejects_a_second_design_in_the_same_project(self) -> None:
        root = self.make_repo()
        self.add_design(root, "star-lang", "STAR-LANG-001.org", active=True)
        design = self.add_design(root, "star-lang", "STAR-LANG-002.org")
        result = self.run_script(root, "implement.py", str(design.relative_to(root)))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("implementation slot for project star-lang occupied", result.stderr)

    def test_status_json_groups_active_designs_by_project(self) -> None:
        root = self.make_repo()
        self.add_design(root, "star-lang", "STAR-LANG-001.org", active=True)
        self.add_design(root, "quasar", "QUASAR-002.org", active=True)
        result = self.run_script(root, "implement.py", "--status", "--json")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        payload = json.loads(result.stdout)
        self.assertEqual(set(payload["projects"]), {"quasar", "star-lang"})
        self.assertTrue(payload["valid"])

    def test_mark_design_requires_project_when_multiple_slots_are_active(self) -> None:
        root = self.make_repo()
        self.add_design(root, "star-lang", "STAR-LANG-001.org", active=True)
        self.add_design(root, "quasar", "QUASAR-002.org", active=True)
        ambiguous = self.run_script(
            root, "mark-design.py", "implemented", "--summary", "done"
        )
        self.assertNotEqual(ambiguous.returncode, 0)
        self.assertIn("--project <project>", ambiguous.stderr)
        selected = self.run_script(
            root,
            "mark-design.py",
            "implemented",
            "--project",
            "star-lang",
            "--summary",
            "done",
        )
        self.assertEqual(selected.returncode, 0, selected.stdout + selected.stderr)
        events = [
            json.loads(line)
            for line in (root / "roam" / ".implemented").read_text().splitlines()
        ]
        self.assertEqual(
            events[0]["active_path"],
            "roam/implement/star-lang/STAR-LANG-001.org",
        )

    def test_sync_clears_only_working_copies_with_synced_events(self) -> None:
        root = self.make_repo()
        self.add_design(root, "star-lang", "STAR-LANG-001.org", active=True)
        self.add_design(root, "quasar", "QUASAR-002.org", active=True)
        marked = self.run_script(
            root,
            "mark-design.py",
            "implemented",
            "--project",
            "star-lang",
            "--summary",
            "done",
        )
        self.assertEqual(marked.returncode, 0, marked.stdout + marked.stderr)
        synced = self.run_script(root, "sync.py")
        self.assertEqual(synced.returncode, 0, synced.stdout + synced.stderr)
        self.assertFalse(
            (root / "roam" / "implement" / "star-lang" / "STAR-LANG-001.org").exists()
        )
        self.assertTrue(
            (root / "roam" / "implement" / "quasar" / "QUASAR-002.org").exists()
        )

    @staticmethod
    def file_id(text: str) -> str:
        for line in text.splitlines():
            if line.upper().startswith(":ID:"):
                return line.split(None, 1)[1]
        raise AssertionError("missing file ID")


if __name__ == "__main__":
    unittest.main()
