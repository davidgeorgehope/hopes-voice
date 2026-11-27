"""Unit tests for PECS image margin trimming (no xAI calls)."""

from pathlib import Path

from PIL import Image, ImageDraw

from app.image_trim import (
    MARGIN_FRACTION,
    content_bbox,
    trim_and_pad,
    trim_and_pad_file,
)


def _synthetic_card(size: int = 200, box: tuple[int, int, int, int] = (80, 80, 119, 119)) -> Image.Image:
    """White square with a solid black subject well inside the frame."""
    image = Image.new("RGB", (size, size), (255, 255, 255))
    draw = ImageDraw.Draw(image)
    draw.rectangle(box, fill=(10, 10, 10))
    return image


def test_content_bbox_finds_the_subject():
    image = _synthetic_card()
    assert content_bbox(image) == (80, 80, 120, 120)


def test_trim_and_pad_subject_fills_about_eighty_eight_percent():
    image = _synthetic_card()
    trimmed = trim_and_pad(image, margin_fraction=MARGIN_FRACTION)
    bbox = content_bbox(trimmed)
    assert bbox is not None
    left, top, right, bottom = bbox
    content = max(right - left, bottom - top)
    fill = content / trimmed.size[0]
    # 1 - 2*0.06 = 0.88, allow a little rounding slack.
    assert 0.84 <= fill <= 0.92
    # Subject stays centered-ish on the square canvas.
    assert abs((left + right) / 2 - trimmed.size[0] / 2) <= 2
    assert abs((top + bottom) / 2 - trimmed.size[1] / 2) <= 2
    # Margins are near-white.
    assert content_bbox(trimmed.crop((0, 0, trimmed.size[0], 2))) is None


def test_trim_and_pad_is_idempotent():
    first = trim_and_pad(_synthetic_card())
    second = trim_and_pad(first)
    assert first.size == second.size
    assert content_bbox(first) == content_bbox(second)


def test_all_white_image_is_left_alone():
    white = Image.new("RGB", (64, 64), (255, 255, 255))
    assert content_bbox(white) is None
    out = trim_and_pad(white)
    assert out.size == white.size


def test_trim_and_pad_file_rewrites_png(tmp_path: Path):
    path = tmp_path / "image.png"
    _synthetic_card().save(path)
    original = path.read_bytes()
    assert trim_and_pad_file(path) is True
    assert path.read_bytes() != original
    with Image.open(path) as written:
        written.load()
        bbox = content_bbox(written)
    assert bbox is not None
    content = max(bbox[2] - bbox[0], bbox[3] - bbox[1])
    assert content / Image.open(path).size[0] >= 0.84
