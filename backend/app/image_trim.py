"""Trim near-white margins from PECS card images and re-pad to a consistent margin."""

from __future__ import annotations

from pathlib import Path

from PIL import Image

# 255 * 0.92 ≈ 235: treat near-white (and near-transparent) pixels as margin.
WHITE_THRESHOLD = 235
MARGIN_FRACTION = 0.06


def content_bbox(
    image: Image.Image, white_threshold: int = WHITE_THRESHOLD
) -> tuple[int, int, int, int] | None:
    """Return the bounding box of non-near-white pixels, or None if the image is empty."""
    rgba = image.convert("RGBA")
    pixels = rgba.load()
    width, height = rgba.size
    min_x, min_y = width, height
    max_x, max_y = -1, -1
    for y in range(height):
        for x in range(width):
            r, g, b, a = pixels[x, y]
            is_background = a < 8 or (r >= white_threshold and g >= white_threshold and b >= white_threshold)
            if not is_background:
                if x < min_x:
                    min_x = x
                if y < min_y:
                    min_y = y
                if x > max_x:
                    max_x = x
                if y > max_y:
                    max_y = y
    if max_x < 0:
        return None
    return (min_x, min_y, max_x + 1, max_y + 1)


def trim_and_pad(
    image: Image.Image,
    margin_fraction: float = MARGIN_FRACTION,
    white_threshold: int = WHITE_THRESHOLD,
) -> Image.Image:
    """Crop near-white margins and re-pad so the subject fills (1 - 2*margin) of a square canvas."""
    bbox = content_bbox(image, white_threshold=white_threshold)
    if bbox is None:
        return image

    cropped = image.convert("RGBA").crop(bbox)
    content_w, content_h = cropped.size
    fill = max(1.0 - 2.0 * margin_fraction, 0.5)
    canvas = int(round(max(content_w, content_h) / fill))
    canvas = max(canvas, max(content_w, content_h) + 2)

    out = Image.new("RGBA", (canvas, canvas), (255, 255, 255, 255))
    offset = ((canvas - content_w) // 2, (canvas - content_h) // 2)
    out.paste(cropped, offset, cropped)
    return out.convert("RGB")


def trim_and_pad_file(
    path: Path,
    margin_fraction: float = MARGIN_FRACTION,
    white_threshold: int = WHITE_THRESHOLD,
) -> bool:
    """Rewrite *path* in place with a trimmed, re-padded image. Returns True if bytes changed."""
    original = path.read_bytes()
    with Image.open(path) as src:
        src.load()
        trimmed = trim_and_pad(src, margin_fraction=margin_fraction, white_threshold=white_threshold)
    tmp = path.with_suffix(path.suffix + ".tmp")
    trimmed.save(tmp, format="PNG")
    new_bytes = tmp.read_bytes()
    if new_bytes == original:
        tmp.unlink(missing_ok=True)
        return False
    tmp.replace(path)
    return True
