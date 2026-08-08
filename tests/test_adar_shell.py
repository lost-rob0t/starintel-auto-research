from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "pages" / "static"
IMPLEMENT = ROOT / "roam" / "implement" / "auto-dig" / "ADAR-001-auto-dig-auto-research-dashboard-and-navigation.org"
APPROVAL = ROOT / "roam" / "research" / "auto-dig" / "ADAR-APPROVAL-001-dashboard-ux.org"


class AdarShellTests(unittest.TestCase):
    def test_research_shell_links_back_to_auto_dig(self) -> None:
        shell = (STATIC / "site.js").read_text(encoding="utf-8")
        self.assertIn("https://auto-dig.starintel.actor/", shell)
        self.assertIn("Auto-Dig ↗", shell)
        self.assertIn("site-core.js", shell)

    def test_existing_site_runtime_is_preserved_as_core(self) -> None:
        core = (STATIC / "site-core.js").read_text(encoding="utf-8")
        self.assertIn("startSearch();", core)
        self.assertIn("startGraph();", core)

    def test_shared_shell_css_preserves_read_mode(self) -> None:
        css = (STATIC / "adar-shell.css").read_text(encoding="utf-8")
        self.assertIn("IBM Plex Sans", css)
        self.assertIn(".site-header", css)
        self.assertNotIn(".site-main { max-width: none", css)

    def test_approval_activates_implementation_slot(self) -> None:
        self.assertTrue(IMPLEMENT.exists())
        approval = APPROVAL.read_text(encoding="utf-8")
        self.assertIn("explicitly approved", approval)
        self.assertIn("| 0.1.0", approval)
        self.assertIn("| Yes |", approval)


if __name__ == "__main__":
    unittest.main()
