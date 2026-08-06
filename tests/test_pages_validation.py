from __future__ import annotations

import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CHECKER = ROOT / "scripts" / "check-pages-links.py"


class PagesValidationTests(unittest.TestCase):
    def make_site(self, body: str = "") -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        site = Path(temporary.name)
        (site / "index.html").write_text(
            "<!doctype html><html><body><h1 id='top'>Test</h1>"
            f"{body}</body></html>",
            encoding="utf-8",
        )
        records = [{"url": "index.html"}]
        (site / "search-index.json").write_text(
            json.dumps(records), encoding="utf-8"
        )
        (site / "graph.json").write_text(
            json.dumps({"nodes": records, "edges": []}), encoding="utf-8"
        )
        (site / "CNAME").write_text(
            "auto-research.starintel.actor\n", encoding="utf-8"
        )
        (site / "deployment.json").write_text(
            json.dumps({"domain": "auto-research.starintel.actor"}),
            encoding="utf-8",
        )
        return site

    def run_checker(self, site: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(CHECKER), str(site)],
            cwd=ROOT,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_valid_site_passes(self) -> None:
        site = self.make_site("<a href='#top'>Top</a>")
        result = self.run_checker(site)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("custom domain, and secret scan passed", result.stdout)

    def test_github_io_link_fails(self) -> None:
        site = self.make_site(
            "<a href='https://lost-rob0t.github.io/starintel-auto-research/'>old</a>"
        )
        result = self.run_checker(site)
        self.assertEqual(result.returncode, 1)
        self.assertIn("prohibited github.io publication link", result.stderr)

    def test_high_confidence_secret_fails(self) -> None:
        site = self.make_site(
            "<pre>Authorization: Bearer " + "A" * 64 + "</pre>"
        )
        result = self.run_checker(site)
        self.assertEqual(result.returncode, 1)
        self.assertIn("possible raw secret (unredacted-bearer-token)", result.stderr)

    def test_redacted_examples_are_allowed(self) -> None:
        site = self.make_site(
            "<pre>Authorization: Bearer &lt;redacted&gt;\n"
            "apiKey: nc_live_••••</pre>"
        )
        result = self.run_checker(site)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_wrong_cname_fails(self) -> None:
        site = self.make_site()
        (site / "CNAME").write_text("example.github.io\n", encoding="utf-8")
        result = self.run_checker(site)
        self.assertEqual(result.returncode, 1)
        self.assertIn("expected auto-research.starintel.actor", result.stderr)


if __name__ == "__main__":
    unittest.main()
