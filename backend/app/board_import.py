"""Validate a bestwishes.board/v1 document. Errors are listed; callers must not half-import."""

from __future__ import annotations

import json
from pathlib import Path
from typing import Any

FORMAT_VERSION = "bestwishes.board/v1"
ALLOWED_TYPES = {"word", "folder", "action"}
ALLOWED_ACTIONS = {"back", "home", "clear", "delete-last", "speak-bar"}
ALLOWED_IMAGE_SOURCES = {"generate", "file", "none"}


def load_document(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def validate(document: dict[str, Any]) -> list[str]:
    errors: list[str] = []
    if not isinstance(document, dict):
        return ["Document must be a JSON object."]

    fmt = document.get("format")
    if fmt != FORMAT_VERSION:
        errors.append(f'format must be "{FORMAT_VERSION}" (got "{fmt}").')

    profile = document.get("profile") or {}
    if not isinstance(profile, dict):
        errors.append("profile must be an object.")
        profile = {}

    home = profile.get("homeBoard") or ""
    if not home:
        errors.append("profile.homeBoard is required.")

    grid = profile.get("grid") or {}
    if not isinstance(grid, dict):
        errors.append("profile.grid must be an object.")
        grid = {}
    rows = _as_int(grid.get("rows"))
    cols = _as_int(grid.get("cols"))
    if rows is None or rows < 1:
        errors.append("profile.grid.rows must be at least 1.")
        rows = rows or 0
    if cols is None or cols < 1:
        errors.append("profile.grid.cols must be at least 1.")
        cols = cols or 0

    boards = document.get("boards")
    if not isinstance(boards, list) or not boards:
        errors.append("boards must contain at least one board.")
        return errors

    board_ids: set[str] = set()
    for board in boards:
        if not isinstance(board, dict):
            errors.append("Each board must be an object.")
            continue
        board_id = board.get("id") or ""
        if not board_id:
            errors.append("A board is missing an id.")
            continue
        if board_id in board_ids:
            errors.append(f'Duplicate board id "{board_id}".')
        board_ids.add(board_id)

    if home and home not in board_ids:
        errors.append(f'profile.homeBoard "{home}" does not match any board id.')

    cell_ids: set[str] = set()
    for board in boards:
        if not isinstance(board, dict):
            continue
        board_id = board.get("id") or ""
        board_rows = _as_int(board.get("rows")) or rows
        board_cols = _as_int(board.get("cols")) or cols
        if board_rows < 1 or board_cols < 1:
            errors.append(f'Board "{board_id}" has an invalid grid size ({board_rows}×{board_cols}).')
        cells = board.get("cells") or []
        if not isinstance(cells, list):
            errors.append(f'Board "{board_id}" cells must be an array.')
            continue
        seen_positions: set[tuple[int, int]] = set()
        for cell in cells:
            if not isinstance(cell, dict):
                errors.append(f'Board "{board_id}" has a cell that is not an object.')
                continue
            cell_id = cell.get("id") or ""
            if not cell_id:
                errors.append(f'Board "{board_id}" has a cell with no id.')
            elif cell_id in cell_ids:
                errors.append(f'Duplicate cell id "{cell_id}".')
            else:
                cell_ids.add(cell_id)
            row = _as_int(cell.get("row"))
            col = _as_int(cell.get("col"))
            if row is None or col is None:
                errors.append(f'Cell "{cell_id or "?"}" is missing row or col.')
                continue
            if row < 0 or col < 0 or row >= board_rows or col >= board_cols:
                errors.append(
                    f'Cell "{cell_id}" at {row},{col} does not fit board "{board_id}" ({board_rows}×{board_cols}).'
                )
            pos = (row, col)
            if pos in seen_positions:
                errors.append(f'Board "{board_id}" has two cells at row {row}, column {col}.')
            seen_positions.add(pos)
            typ = cell.get("type") or "word"
            if typ not in ALLOWED_TYPES:
                errors.append(f'Cell "{cell_id}" has unknown type "{typ}".')
            if typ == "folder":
                target = cell.get("target") or ""
                if not target:
                    errors.append(f'Folder cell "{cell_id}" is missing a target.')
                elif target not in board_ids:
                    errors.append(f'Cell "{cell_id}" targets missing board "{target}".')
            if typ == "action":
                action = cell.get("action") or ""
                if not action:
                    errors.append(f'Action cell "{cell_id}" is missing an action.')
                elif action not in ALLOWED_ACTIONS:
                    errors.append(f'Cell "{cell_id}" has unknown action "{action}".')
            image = cell.get("image")
            if isinstance(image, dict):
                source = image.get("source") or "generate"
                if source not in ALLOWED_IMAGE_SOURCES:
                    errors.append(f'Cell "{cell_id}" has unknown image.source "{source}".')
                if source == "file" and not (image.get("path") or "").strip():
                    errors.append(f'Cell "{cell_id}" has image.source "file" but no path.')

    return errors


def _as_int(raw: Any) -> int | None:
    if isinstance(raw, bool) or raw is None:
        return None
    if isinstance(raw, int):
        return raw
    if isinstance(raw, float) and raw.is_integer():
        return int(raw)
    if isinstance(raw, str) and raw.lstrip("-").isdigit():
        return int(raw)
    return None
