from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "pages" / "static"
IMPLEMENT = ROOT / "roam" / "implement" / "auto-dig" / "ADAR-001-auto-dig-auto-research-dashboard-and-navigation.org"
APPROVAL = ROOT / "roam" / "research" / "auto-dig" / "ADAR-APPROVAL-001-dashboard-ux.org"


class AdarShellTests(unittest.TestCase):
    def test_research_shell_is_rendered_without_javascript(self) -> None:
        pages = (ROOT / "lisp" / "starintel" / "pages.el").read_text(encoding="utf-8")
        self.assertIn("https://auto-dig.starintel.actor/", pages)
        self.assertIn("si-skip-link", pages)
        self.assertIn("si-topbar__nav", pages)
        self.assertIn("starintel-pages--footer-html", pages)

    def test_site_runtime_only_loads_page_behavior(self) -> None:
        shell = (STATIC / "site.js").read_text(encoding="utf-8")
        self.assertIn("site-core.js", shell)
        self.assertIn("graph.js", shell)
        self.assertNotIn("innerHTML", shell)
        self.assertNotIn("adar-shell", shell)

    def test_existing_site_runtime_is_preserved_as_core(self) -> None:
        core = (STATIC / "site-core.js").read_text(encoding="utf-8")
        self.assertIn("startSearch();", core)
        self.assertIn("startGraph();", core)

    def test_shared_shell_uses_canonical_obsidian_gold_tokens(self) -> None:
        css = (STATIC / "site.css").read_text(encoding="utf-8").lower()
        self.assertIn('data-si-theme="obsidian-gold"', css)
        self.assertIn("--si-bg-canvas: #090807", css)
        self.assertIn("--si-accent-primary: #e0b04a", css)
        self.assertIn("var(--si-accent-primary)", css)
        self.assertIn(".si-org", css)

    def test_homepage_uses_canonical_identity_asset(self) -> None:
        pages = (ROOT / "lisp" / "starintel" / "pages.el").read_text(encoding="utf-8")
        self.assertIn("lambda-network.svg", pages)
        self.assertTrue((STATIC / "lambda-network.svg").exists())

    def test_approval_activates_implementation_slot(self) -> None:
        self.assertTrue(IMPLEMENT.exists())
        approval = APPROVAL.read_text(encoding="utf-8")
        self.assertIn("explicitly approved", approval)
        self.assertIn("| 0.1.0", approval)
        self.assertIn("| Yes |", approval)


if __name__ == "__main__":
    unittest.main()
