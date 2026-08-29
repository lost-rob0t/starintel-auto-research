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


class ResearchPersistencePromptTests(unittest.TestCase):
    def test_source_worker_requires_durable_org_artifact(self) -> None:
        text = (
            ROOT
            / "agent-zero/usr/agents/starintel-source-enrichment/prompts/agent.system.main.specifics.md"
        ).read_text(encoding="utf-8")
        self.assertIn("Every research pass MUST persist", text)
        self.assertIn(
            "roam/research/ardr-issues/ARDR-ISSUE-<issue-number>-<slug>.org",
            text,
        )
        self.assertIn("scripts/save-research.py", text)
        self.assertIn("A pass is not complete until", text)

    def test_coordinator_rejects_issue_only_research(self) -> None:
        text = (
            ROOT
            / "agent-zero/usr/agents/starintel-adard-gated/prompts/agent.system.main.specifics.md"
        ).read_text(encoding="utf-8")
        self.assertIn("Research issue/file gate", text)
        self.assertIn(
            "After every research delegation, verify the worker reports exact research paths",
            text,
        )
        self.assertIn("If findings exist only in issue prose/chat/task output", text)
        self.assertIn("do not advance", text)


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
