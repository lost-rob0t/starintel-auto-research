from __future__ import annotations

import argparse
import importlib.util
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "scripts"

if str(SCRIPTS) not in sys.path:
    sys.path.insert(0, str(SCRIPTS))

SPEC = importlib.util.spec_from_file_location("save_research", SCRIPTS / "save-research.py")
assert SPEC is not None and SPEC.loader is not None
SAVE_RESEARCH = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SAVE_RESEARCH)


class RetiredWorkerPromptTests(unittest.TestCase):
    def test_source_worker_is_fail_closed_migration_tombstone(self) -> None:
        text = (
            ROOT
            / "agent-zero/usr/agents/starintel-source-enrichment/prompts/agent.system.main.specifics.md"
        ).read_text(encoding="utf-8")
        self.assertIn("RETIRED PROFILE — STOP", text)
        self.assertIn("lost-rob0t/hackmode", text)
        self.assertIn("cyber / BBP", text)
        self.assertIn("Do **not** continue general StarIntel", text)

    def test_coordinator_is_fail_closed_migration_tombstone(self) -> None:
        text = (
            ROOT
            / "agent-zero/usr/agents/starintel-adard-gated/prompts/agent.system.main.specifics.md"
        ).read_text(encoding="utf-8")
        self.assertIn("RETIRED PROFILE — STOP", text)
        self.assertIn("hackmode-rage-database", text)
        self.assertIn("hackmode-rage-hackpert", text)
        self.assertIn("Do **not** resume StarIntel product", text)


class SaveResearchDocumentTests(unittest.TestCase):
    def test_new_document_is_durable_pending_research_record(self) -> None:
        args = argparse.Namespace(
            title="STAR-RESEARCH-999 Persistence Contract",
            description="Prove every research pass has a durable artifact.",
            finding=["Narrative-only research is not durable."],
            source=["https://example.invalid/source"],
            repository=["lost-rob0t/starintel-auto-research"],
            commit=["deadbeef"],
            design_file=[],
            next_action="Human review.",
        )
        text = SAVE_RESEARCH.new_research_document(
            args,
            state="REVIEW",
            timestamp="2026-08-29T06:41:00-04:00",
            date="2026-08-29",
            project_slug="auto-research",
        )

        self.assertIn(":ID:       starintel-research-auto-research-", text)
        self.assertIn("#+status: REVIEW", text)
        self.assertIn("#+approval_schema: adard.research-approval.v1", text)
        self.assertIn("#+approval_state: PENDING", text)
        self.assertIn("* Approval Table", text)
        self.assertIn("* Changelog", text)
        self.assertIn("* Footnotes and Glossary", text)
        self.assertIn("Narrative-only research is not durable.", text)
        self.assertIn("Retrieved 2026-08-29: https://example.invalid/source", text)
        self.assertNotIn("#+approval_state: APPROVED", text)


if __name__ == "__main__":
    unittest.main()
