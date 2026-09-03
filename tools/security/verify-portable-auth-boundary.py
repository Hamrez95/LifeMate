#!/usr/bin/env python3
"""Fail when portable business migrations contain non-helper auth.* references.

Supabase RLS predicates legitimately use read-only request-context helpers such as
`auth.uid()` and `auth.jwt()`. Portable migrations must still not own, mutate,
grant on, or otherwise depend directly on Supabase Auth schema objects.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
LINE_COMMENT = re.compile(r"--[^\n]*")
ALLOWED_HELPER = re.compile(r"\bauth\.(?:uid|jwt)\s*\(\s*\)", re.IGNORECASE)
AUTH_REFERENCE = re.compile(r"\bauth\.", re.IGNORECASE)


def remove_comments(sql: str) -> str:
    return LINE_COMMENT.sub("", BLOCK_COMMENT.sub("", sql))


def forbidden_auth_references(sql: str) -> list[int]:
    """Return 1-based line numbers containing auth.* after allowed helpers are removed."""
    cleaned = remove_comments(sql)
    sanitized = ALLOWED_HELPER.sub("", cleaned)
    return [
        index
        for index, line in enumerate(sanitized.splitlines(), start=1)
        if AUTH_REFERENCE.search(line)
    ]


def scan(paths: list[Path]) -> list[str]:
    findings: list[str] = []
    for root in paths:
        candidates = [root] if root.is_file() else sorted(root.rglob("*.sql"))
        for path in candidates:
            if not path.is_file() or path.suffix.lower() != ".sql":
                continue
            lines = forbidden_auth_references(path.read_text(encoding="utf-8"))
            findings.extend(f"{path}:{line}" for line in lines)
    return findings


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("paths", nargs="+", type=Path)
    args = parser.parse_args(argv)

    findings = scan(args.paths)
    if findings:
        print(
            "Portable business migrations may use auth.uid()/auth.jwt() only; "
            "other auth.* references belong outside the portable migration owner.",
            file=sys.stderr,
        )
        for finding in findings:
            print(f"- {finding}", file=sys.stderr)
        return 1

    print("Portable Auth boundary passed: only approved auth context helpers are referenced.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
