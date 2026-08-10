from __future__ import annotations

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
STATIC = ROOT / "pages" / "static"


class GraphWorkspaceTests(unittest.TestCase):
    def test_graph_page_uses_dedicated_runtime(self) -> None:
        shell = (STATIC / "site.js").read_text(encoding="utf-8")
        self.assertIn('document.getElementById("graph-canvas")', shell)
        self.assertIn('"graph.js"', shell)
        self.assertIn('"site-core.js"', shell)

    def test_graph_runtime_colors_nodes_by_type(self) -> None:
        runtime = (STATIC / "graph.js").read_text(encoding="utf-8")
        self.assertIn("KIND_COLORS", runtime)
        self.assertIn("node.kind || node.type", runtime)
        self.assertIn("colorForKind(kind)", runtime)
        self.assertIn("graph-kind-filter", runtime)
        self.assertIn("hiddenKinds", runtime)

    def test_graph_runtime_supports_navigation_and_focus(self) -> None:
        runtime = (STATIC / "graph.js").read_text(encoding="utf-8")
        self.assertIn("fitView", runtime)
        self.assertIn("setZoom", runtime)
        self.assertIn('mode: "pan"', runtime)
        self.assertIn("Focus neighborhood", runtime)
        self.assertIn("graph-search", runtime)

    def test_graph_styles_define_workspace_and_mobile_inspector(self) -> None:
        css = (STATIC / "graph.css").read_text(encoding="utf-8")
        self.assertIn(".graph-workspace", css)
        self.assertIn(".graph-kind-filter", css)
        self.assertIn(".graph-inspector", css)
        self.assertIn("@media (max-width: 58rem)", css)


if __name__ == "__main__":
    unittest.main()
