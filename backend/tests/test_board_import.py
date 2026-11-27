from pathlib import Path
import copy
import json

from app.board_import import validate

FIXTURE = Path(__file__).parent / "fixtures" / "sample.board.json"


def _sample() -> dict:
    return json.loads(FIXTURE.read_text())


def test_sample_fixture_is_valid():
    errors = validate(_sample())
    assert errors == []


def test_wrong_format_is_rejected():
    doc = _sample()
    doc["format"] = "bestwishes.board/v0"
    errors = validate(doc)
    assert any("format must be" in item for item in errors)


def test_duplicate_cell_ids_are_listed():
    doc = _sample()
    doc["boards"][1]["cells"][0]["id"] = "help"
    errors = validate(doc)
    assert any("Duplicate cell id" in item and "help" in item for item in errors)


def test_overlapping_positions_are_listed():
    doc = _sample()
    extra = copy.deepcopy(doc["boards"][0]["cells"][0])
    extra["id"] = "want-copy"
    extra["row"] = 0
    extra["col"] = 0
    doc["boards"][0]["cells"].append(extra)
    errors = validate(doc)
    assert any("two cells at row 0, column 0" in item for item in errors)


def test_missing_folder_target_is_listed():
    doc = _sample()
    doc["boards"][0]["cells"][0]["target"] = "missing-board"
    errors = validate(doc)
    assert any("missing board" in item and "missing-board" in item for item in errors)


def test_cell_outside_grid_is_listed():
    doc = _sample()
    doc["boards"][0]["cells"][0]["row"] = 99
    errors = validate(doc)
    assert any("does not fit board" in item for item in errors)


def test_invalid_file_collects_every_error():
    doc = _sample()
    doc["boards"][0]["cells"][0]["target"] = "missing-board"
    doc["boards"][0]["cells"][1]["id"] = "want"
    doc["boards"][1]["cells"][0]["row"] = 40
    errors = validate(doc)
    assert len(errors) >= 3
