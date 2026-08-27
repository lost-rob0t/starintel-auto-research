from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from research_queue import load_items  # noqa: E402


spec = importlib.util.spec_from_file_location(
    "build_research_pending", SCRIPTS / "build-research-pending.py"
)
assert spec and spec.loader
build_research_pending = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build_research_pending)


def org_text(
    *,
    title: str,
    status: str,
    approval_state: str | None = None,
    approval_schema: str | None = None,
) -> str:
    lines = [
        ":PROPERTIES:",
        f":ID: test-{title.lower().replace(' ', '-')}",
        ":END:",
        f"#+title: {title}",
        f"#+status: {status}",
        "#+last_modified: [2026-08-27 Thu]",
    ]
    if approval_schema is not None:
        lines.append(f"#+approval_schema: {approval_schema}")
    if approval_state is not None:
        lines.append(f"#+approval_state: {approval_state}")
    lines.extend(["", "* Research", "Body.", ""])
    return "\n".join(lines)


class ResearchPendingTests(unittest.TestCase):
    def make_root(self) -> Path:
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        root = Path(temporary.name)
        (root / "roam" / "research").mkdir(parents=True)
        return root

    def write(self, root: Path, relative: str, text: str) -> Path:
        path = root / "roam" / "research" / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        return path

    def test_canonical_queue_requires_pending_approval_state(self) -> None:
        root = self.make_root()
        self.write(
            root,
            "rlm/pending.org",
            org_text(
                title="Pending",
                status="REVIEW",
                approval_schema="prolog-rlm.research-approval.v1",
                approval_state="PENDING",
            ),
        )
        self.write(
            root,
            "rlm/approved.org",
            org_text(
                title="Approved",
                status="REVIEW",
                approval_schema="prolog-rlm.research-approval.v1",
                approval_state="APPROVED",
            ),
        )
        self.write(
            root,
            "rlm/rejected.org",
            org_text(
                title="Rejected",
                status="REVIEW",
                approval_schema="prolog-rlm.research-approval.v1",
                approval_state="REJECTED",
            ),
        )

        items = load_items(root)
        self.assertEqual([item.title for item in items], ["Pending"])
        self.assertFalse(items[0].legacy)
        self.assertEqual(items[0].approval_state, "PENDING")

    def test_legacy_queue_is_only_review_researched_verified(self) -> None:
        root = self.make_root()
        for status in ("REVIEW", "RESEARCHED", "VERIFIED"):
            self.write(
                root,
                f"legacy/{status.lower()}.org",
                org_text(title=status, status=status),
            )
        for status in (
            "DRAFT",
            "RESEARCHING",
            "APPROVED",
            "DONE",
            "REJECTED",
            "SUPERSEDED",
            "implemented-prototype",
            "accepted-for-realization",
        ):
            self.write(
                root,
                f"legacy/excluded-{status.lower()}.org",
                org_text(title=f"Excluded {status}", status=status),
            )
        self.write(root, "legacy/missing.org", org_text(title="Missing", status=""))

        items = load_items(root)
        self.assertEqual({item.status for item in items}, {"REVIEW", "RESEARCHED", "VERIFIED"})
        self.assertTrue(all(item.legacy for item in items))

    def test_auxiliary_files_and_partial_canonical_metadata_are_not_queued(self) -> None:
        root = self.make_root()
        for name in ("index.org", "sources.org", "search-log.org"):
            self.write(root, f"noise/{name}", org_text(title=name, status="REVIEW"))
        self.write(
            root,
            "noise/partial.org",
            org_text(
                title="Partial canonical",
                status="REVIEW",
                approval_schema="prolog-rlm.research-approval.v1",
            ),
        )

        self.assertEqual(load_items(root), [])

    def test_dashboard_hides_legacy_by_default_and_exposes_filter_fields(self) -> None:
        root = self.make_root()
        self.write(
            root,
            "rlm/canonical.org",
            org_text(
                title="Canonical pending",
                status="REVIEW",
                approval_schema="prolog-rlm.research-approval.v1",
                approval_state="PENDING",
            ),
        )
        self.write(root, "starintel/legacy.org", org_text(title="Legacy ready", status="VERIFIED"))

        document = build_research_pending.render_dashboard(root)
        self.assertIn("Canonical pending", document)
        self.assertIn("Legacy ready", document)
        self.assertIn('class="research-row is-legacy" hidden', document)
        self.assertIn('id="research-search-field"', document)
        self.assertIn('<option value="repository">Repository</option>', document)
        self.assertIn('<option value="path">Path</option>', document)
        self.assertIn("Public API only · no browser token", document)
        self.assertIn("../assets/research-pending.js", document)

    def test_dashboard_writes_extensionless_pages_route(self) -> None:
        root = self.make_root()
        self.write(
            root,
            "rlm/pending.org",
            org_text(
                title="Pending",
                status="REVIEW",
                approval_schema="prolog-rlm.research-approval.v1",
                approval_state="PENDING",
            ),
        )
        site = root / "_site"
        output = build_research_pending.write_dashboard(site, root)
        self.assertEqual(output, site / "research-pending" / "index.html")
        self.assertTrue(output.is_file())


if __name__ == "__main__":
    unittest.main()
