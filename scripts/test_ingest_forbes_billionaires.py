from __future__ import annotations

import importlib.util
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent / "ingest_forbes_billionaires.py"
SPEC = importlib.util.spec_from_file_location("forbes_ingest", SCRIPT)
assert SPEC and SPEC.loader
MODULE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(MODULE)


class ForbesIngestTests(unittest.TestCase):
    def setUp(self) -> None:
        self.payload = {
            "personList": {
                "personsLists": [
                    {
                        "rank": 1,
                        "uri": "ada-example",
                        "personName": "Ada Example",
                        "source": "Example Systems",
                        "industries": ["Technology"],
                        "countryOfCitizenship": "United States",
                        "finalWorth": 123400,
                        "estWorthPrev": 120000,
                    },
                    {
                        "position": 2,
                        "uri": "grace-example",
                        "personName": "Grace Example",
                        "source": "Compilers",
                        "industries": "Technology",
                        "countryOfCitizenship": "United States",
                        "finalWorth": 99000,
                        "estWorthPrev": 99500,
                    },
                ]
            }
        }

    def test_extract_and_normalize(self) -> None:
        record = MODULE.extract(self.payload)[0]
        doc = MODULE.normalize(record, "2026-08-03T00:00:00Z")
        self.assertEqual("person", doc["dtype"])
        self.assertEqual(1, doc["rank"])
        self.assertEqual(123_400_000_000, doc["net_worth_usd"])
        self.assertEqual(3_400_000_000, doc["net_worth_change_usd"])

    def test_ingest_writes_latest_and_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory)
            manifest = MODULE.ingest(self.payload, output, 2, "fixture")
            self.assertEqual(2, manifest["record_count"])
            self.assertEqual(2, len((output / "latest.jsonl").read_text().splitlines()))
            self.assertTrue((output / "manifest.json").exists())

    def test_rejects_small_results(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            with self.assertRaises(MODULE.IngestError):
                MODULE.ingest(self.payload, Path(directory), 3, "fixture")


if __name__ == "__main__":
    unittest.main()
