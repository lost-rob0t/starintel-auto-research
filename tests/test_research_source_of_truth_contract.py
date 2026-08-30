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

    def test_research_worker_is_retired_in_favor_of_hackmode(self) -> None:
        text = (
            ROOT
            / "agent-zero/usr/agents/starintel-source-enrichment/prompts/agent.system.main.specifics.md"
        ).read_text(encoding="utf-8")
        self.assertIn("RETIRED PROFILE — STOP", text)
        self.assertIn("lost-rob0t/hackmode", text)
        self.assertIn("authorized cyber / BBP objective", text)

    def test_coordinator_is_retired_in_favor_of_hackmode(self) -> None:
        text = (
            ROOT
            / "agent-zero/usr/agents/starintel-adard-gated/prompts/agent.system.main.specifics.md"
        ).read_text(encoding="utf-8")
        self.assertIn("RETIRED PROFILE — STOP", text)
        self.assertIn("hackmode-rage-database", text)
        self.assertIn("hackmode-rage-hackpert", text)
        self.assertIn("Ordinary StarIntel product work", text)


if __name__ == "__main__":
    unittest.main()
