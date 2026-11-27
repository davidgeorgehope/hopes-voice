#!/usr/bin/env python3
"""Validate a bestwishes.board/v1 JSON file. Exit 0 only when there are no errors."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# Allow running from a checkout without installing the package.
ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))

from app.board_import import load_document, validate  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path, help="Path to a bestwishes.board/v1 JSON file")
    args = parser.parse_args()
    path: Path = args.path
    if not path.is_file():
        print(f"error: file not found: {path}", file=sys.stderr)
        return 2
    try:
        document = load_document(path)
    except json.JSONDecodeError as exc:
        print(f"error: invalid JSON: {exc}", file=sys.stderr)
        return 2
    errors = validate(document)
    if errors:
        print(f"{len(errors)} error(s) in {path}:")
        for item in errors:
            print(f"- {item}")
        return 1
    boards = document.get("boards") or []
    cells = sum(len(board.get("cells") or []) for board in boards if isinstance(board, dict))
    print(f"ok: {len(boards)} board(s), {cells} cell(s), 0 errors")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
