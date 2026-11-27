#!/usr/bin/env python3
"""One-off: re-trim existing PECS card images in a Hope's Voice data directory.

Backs up originals first, then writes trimmed/re-padded PNGs in place.
Does not call the xAI API and does not touch audio or board.json.

Usage:
  python retrim_card_images.py --data-dir /var/lib/hopesvoice/data
  python retrim_card_images.py --data-dir /var/lib/hopesvoice/data --dry-run
"""

from __future__ import annotations

import argparse
import shutil
import sys
from datetime import datetime, timezone
from pathlib import Path

# Allow `python scripts/retrim_card_images.py` from the backend directory.
BACKEND_ROOT = Path(__file__).resolve().parent.parent
if str(BACKEND_ROOT) not in sys.path:
    sys.path.insert(0, str(BACKEND_ROOT))

from app.image_trim import trim_and_pad_file  # noqa: E402


def find_card_images(data_dir: Path) -> list[Path]:
    cards = data_dir / "cards"
    if not cards.is_dir():
        return []
    return sorted(path for path in cards.glob("*/image.png") if path.is_file())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--data-dir",
        type=Path,
        required=True,
        help="Hope's Voice data root (contains cards/<slug>/image.png)",
    )
    parser.add_argument(
        "--backup-dir",
        type=Path,
        default=None,
        help="Where to copy originals before rewriting. Default: <data-dir>/../image-backups/<timestamp>",
    )
    parser.add_argument("--dry-run", action="store_true", help="List images without writing")
    args = parser.parse_args()

    data_dir = args.data_dir.expanduser().resolve()
    images = find_card_images(data_dir)
    if not images:
        print(f"No card images found under {data_dir / 'cards'}", file=sys.stderr)
        return 1

    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    backup_dir = (
        args.backup_dir.expanduser().resolve()
        if args.backup_dir
        else (data_dir.parent / "image-backups" / stamp)
    )

    print(f"Found {len(images)} card image(s) in {data_dir}")
    if args.dry_run:
        for path in images:
            print(f"  would trim {path.relative_to(data_dir)}")
        print("Dry run; no files written.")
        return 0

    backup_dir.mkdir(parents=True, exist_ok=True)
    changed = 0
    unchanged = 0
    failed = 0
    for path in images:
        rel = path.relative_to(data_dir)
        dest = backup_dir / rel
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, dest)
        try:
            if trim_and_pad_file(path):
                changed += 1
                print(f"  trimmed {rel}")
            else:
                unchanged += 1
                print(f"  unchanged {rel}")
        except Exception as exc:  # noqa: BLE001 — keep going through the batch
            failed += 1
            # Restore this file from the backup we just made.
            shutil.copy2(dest, path)
            print(f"  FAILED {rel}: {exc}", file=sys.stderr)

    print(
        f"Done. trimmed={changed} unchanged={unchanged} failed={failed}. "
        f"Originals saved in {backup_dir}"
    )
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
