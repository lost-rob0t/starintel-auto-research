#!/usr/bin/env python3
"""Hardened entrypoint for the deterministic Child Identity Firewall.

This wrapper expands restricted child identifiers into common filename and URL
separator variants before invoking the network-free core firewall.
"""

from __future__ import annotations

import argparse
import re
import sys
from typing import Iterable, Sequence

try:
    from scripts.child_identity_firewall import (
        ChildIdentityFirewall as CoreChildIdentityFirewall,
        FirewallResult,
        REDACTED_CHILD,
        REJECTED_QUERY,
        _load_identifiers,
        _read_json,
        _write_json,
    )
except ModuleNotFoundError:
    from child_identity_firewall import (
        ChildIdentityFirewall as CoreChildIdentityFirewall,
        FirewallResult,
        REDACTED_CHILD,
        REJECTED_QUERY,
        _load_identifiers,
        _read_json,
        _write_json,
    )


def expand_identifier_variants(values: Iterable[str]) -> tuple[str, ...]:
    """Return canonical identifiers plus common path and filename variants."""

    variants: set[str] = set()
    for value in values:
        if not isinstance(value, str) or not value.strip():
            continue
        canonical = re.sub(r"\s+", " ", value.strip())
        variants.add(canonical)
        parts = canonical.split(" ")
        if len(parts) > 1:
            for separator in ("-", "_", ".", "+", "%20"):
                variants.add(separator.join(parts))
    return tuple(sorted(variants, key=len, reverse=True))


class ChildIdentityFirewall(CoreChildIdentityFirewall):
    """Core firewall with deterministic identifier-variant expansion."""

    def __init__(
        self,
        *,
        case_id: str,
        known_child_identifiers: Iterable[str] = (),
    ) -> None:
        super().__init__(
            case_id=case_id,
            known_child_identifiers=expand_identifier_variants(known_child_identifiers),
        )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("sanitize", "scan"))
    parser.add_argument("input", help="JSON path or - for stdin")
    parser.add_argument("output", help="JSON path or - for stdout")
    parser.add_argument("--case-id", required=True)
    parser.add_argument("--known-child-identifiers-file")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        firewall = ChildIdentityFirewall(
            case_id=args.case_id,
            known_child_identifiers=_load_identifiers(args.known_child_identifiers_file),
        )
        payload = _read_json(args.input)
        result: FirewallResult
        result = firewall.sanitize(payload) if args.command == "sanitize" else firewall.scan_export(payload)
        _write_json(args.output, result.as_dict())
        return 0 if result.allowed else 2
    except (OSError, ValueError) as error:
        print(f"child identity firewall failed: {type(error).__name__}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    raise SystemExit(main())
