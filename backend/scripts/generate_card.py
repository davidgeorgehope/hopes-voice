#!/usr/bin/env python3
"""One-shot: generate a PECS image + TTS MP3 for a word via xAI (no server)."""

from __future__ import annotations

import asyncio
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

# Allow importing app.main when run from backend root or scripts/
BACKEND_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(BACKEND_ROOT))

import httpx

from app.main import (
    DATA_DIR,
    generate_image,
    generate_tts,
    public_urls,
    slugify,
    write_meta,
)


async def main(word: str) -> int:
    word = word.strip()
    if not word:
        print("Usage: generate_card.py <word>", file=sys.stderr)
        return 2
    slug = slugify(word)
    card_dir = DATA_DIR / slug
    image_file = card_dir / "image.png"
    audio_file = card_dir / "audio.mp3"

    print(f"Generating PECS card for {word!r} (slug={slug}) ...")
    async with httpx.AsyncClient() as client:
        try:
            img_info = await generate_image(client, word, image_file)
            print(f"  image OK: {image_file} ({img_info['bytes']} bytes)")
        except Exception as e:
            print(f"  image FAILED: {e}", file=sys.stderr)
            return 1
        try:
            tts_info = await generate_tts(client, word, audio_file)
            print(f"  audio OK: {audio_file} ({tts_info['bytes']} bytes)")
        except Exception as e:
            print(f"  audio FAILED: {e}", file=sys.stderr)
            return 1

    urls = public_urls(slug)
    meta = {
        "word": word,
        "slug": slug,
        "image_path": str(image_file),
        "audio_path": str(audio_file),
        "image_url": urls["image_url"],
        "audio_url": urls["audio_url"],
        "created_at": datetime.now(timezone.utc).isoformat(),
        "image_bytes": img_info["bytes"],
        "audio_bytes": tts_info["bytes"],
        "image_model": img_info["model"],
        "tts_voice": tts_info["voice_id"],
        "prompt": img_info["prompt"],
    }
    write_meta(slug, meta)
    print(json.dumps(meta, indent=2))
    return 0


if __name__ == "__main__":
    word_arg = " ".join(sys.argv[1:]) if len(sys.argv) > 1 else "ice cream"
    raise SystemExit(asyncio.run(main(word_arg)))
