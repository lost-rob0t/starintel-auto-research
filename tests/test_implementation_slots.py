from __future__ import annotations
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"

class ImplementationSlotTests(unittest.TestCase):
    def make_repo(self) -> Path:
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        root = Path(tmp.name)
        for tree in ("design", "research", "implement", "indexes"):
            (root / "roam" / tree).mkdir(parents=True)
        (root / "roam" / ".implemented").touch()
        (root / "roam" / ".rejected").touch()
        return root

    def add_project(self, root: Path, project: str) -> None:
        for tree in ("design", "research", "implement", "indexes"):
            (root / "roam" / tree / project).mkdir(exist_ok=True)

    def add_design(self, root: Path, project: str, name: str, active: bool = False) -> Path:
        self.add_project(root, project)
        text = f"#+title: {name}\n#+description: test design\n#+status: REVIEW\n"
        canonical = root / "roam" / "design" / project / name
        canonical.write_text(text, encoding="utf-8")
        if active:
            (root / "roam" / "implement" / project / name).write_text(text, encoding="utf-8")
        return canonical

    def run_script(self, root: Path, script: str, *args: str) -> subprocess.CompletedProcess[str]:
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
        self.assertIn("implementation slot for project star-lang contains 2 Org files", result.stdout)

    def test_implement_selects_an_empty_project_slot(self) -> None:
        root = self.make_repo()
        self.add_design(root, "star-lang", "STAR-LANG-001.org", active=True)
        design = self.add_design(root, "quasar", "QUASAR-002.org")
        result = self.run_script(root, "implement.py", str(design.relative_to(root)))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((root / "roam" / "implement" / "quasar" / "QUASAR-002.org").is_file())

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
        ambiguous = self.run_script(root, "mark-design.py", "implemented", "--summary", "done")
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
        events = [json.loads(line) for line in (root / "roam" / ".implemented").read_text().splitlines()]
        self.assertEqual(events[0]["active_path"], "roam/implement/star-lang/STAR-LANG-001.org")

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
        self.assertFalse((root / "roam" / "implement" / "star-lang" / "STAR-LANG-001.org").exists())
        self.assertTrue((root / "roam" / "implement" / "quasar" / "QUASAR-002.org").exists())

if __name__ == "__main__":
    unittest.main()
