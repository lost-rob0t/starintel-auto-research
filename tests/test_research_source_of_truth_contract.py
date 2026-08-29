from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parent.parent


class ResearchSourceOfTruthContractTests(unittest.TestCase):
    def test_save_research_skill_requires_default_checkout_and_stop_on_missing(self) -> None:
        text = (ROOT / "skills/save-research/SKILL.md").read_text(encoding="utf-8")
        self.assertIn("~/starintel/starintel-auto-research", text)
        self.assertIn("If the default checkout does **not** exist, STOP", text)
        self.assertIn("Ask the user to provide the correct path", text)
        self.assertIn("treat GitHub/Forgejo/remote contents as the source of truth", text)

    def test_research_worker_requires_issue_transaction_file(self) -> None:
        text = (
            ROOT
            / "agent-zero/usr/agents/starintel-source-enrichment/prompts/agent.system.main.specifics.md"
        ).read_text(encoding="utf-8")
        self.assertIn("Research issue -> durable file invariant", text)
        self.assertIn("roam/research/ardr-issues/ARDR-ISSUE-<issue-number>-<slug>.org", text)
        self.assertIn("If a research issue already exists without that file", text)

    def test_coordinator_blocks_issue_only_research(self) -> None:
        text = (
            ROOT
            / "agent-zero/usr/agents/starintel-adard-gated/prompts/agent.system.main.specifics.md"
        ).read_text(encoding="utf-8")
        self.assertIn("research issue and its durable Org transaction are one unit", text)
        self.assertIn("findings exist only in issue prose/chat/task output", text)
        self.assertIn("do not advance", text)


if __name__ == "__main__":
    unittest.main()
