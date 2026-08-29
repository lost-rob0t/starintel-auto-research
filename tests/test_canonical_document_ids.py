from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
VALIDATOR_PATH = ROOT / "scripts" / "validate-docs.py"
SPEC = importlib.util.spec_from_file_location("starintel_validate_docs_canonical_test", VALIDATOR_PATH)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load validator: {VALIDATOR_PATH}")
VALIDATOR = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = VALIDATOR
SPEC.loader.exec_module(VALIDATOR)


class CanonicalDocumentIdTests(unittest.TestCase):
    def test_canonical_ids_are_unique_within_document_class(self) -> None:
        claims: dict[tuple[str, str], list[Path]] = {}
        mismatches: list[str] = []

        for path in VALIDATOR.substantive_files(ROOT):
            document_class = VALIDATOR.document_class(path, ROOT)
            identifier = VALIDATOR.canonical_document_id(path)
            if document_class is None or identifier is None:
                continue

            claims.setdefault((document_class, identifier), []).append(path)
            title_identifier = VALIDATOR.canonical_title_id(path.read_text(encoding="utf-8"))
            if title_identifier is not None and title_identifier != identifier:
                mismatches.append(
                    f"{path.relative_to(ROOT)}: filename={identifier} title={title_identifier}"
                )

        collisions = []
        for (document_class, identifier), paths in sorted(claims.items()):
            unique = sorted(set(paths))
            if len(unique) < 2:
                continue
            collisions.append(
                f"{document_class}:{identifier}: "
                + ", ".join(str(path.relative_to(ROOT)) for path in unique)
            )

        self.assertFalse(
            collisions or mismatches,
            "canonical document ID integrity failures:\n"
            + "\n".join([*collisions, *mismatches]),
        )


if __name__ == "__main__":
    unittest.main()
