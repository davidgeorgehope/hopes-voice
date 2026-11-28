"""
AAC backend for Hope's Voice

Caregiver hits this service → xAI generates PECS image + TTS → assets stored
locally. The iPad app only plays local assets (no AI on device).

Board tree (folders + membership) persists in data/board.json.
"""

from __future__ import annotations

import json
import os
import re
import shutil
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx

from app.http_cache import conditional_json
from app.image_trim import trim_and_pad_file
from app.sync import router as sync_router
from fastapi import FastAPI, HTTPException, Query, Request, Response
from fastapi.staticfiles import StaticFiles
from pydantic import BaseModel, Field

# ---------------------------------------------------------------------------
# Paths & config
# ---------------------------------------------------------------------------

BACKEND_ROOT = Path(__file__).resolve().parent.parent
# Tests and local sandboxes can redirect generated assets with BESTWISHES_DATA_DIR.
_data_override = os.environ.get("BESTWISHES_DATA_DIR", "").strip()
DATA_ROOT = Path(_data_override).expanduser().resolve() if _data_override else BACKEND_ROOT / "data"
DATA_DIR = DATA_ROOT / "cards"
SYSTEM_DIR = DATA_ROOT / "system"
BOARD_PATH = DATA_ROOT / "board.json"

DATA_DIR.mkdir(parents=True, exist_ok=True)
SYSTEM_DIR.mkdir(parents=True, exist_ok=True)

FOLDER_IMAGE_URL = "/system/folder.png"

XAI_BASE = "https://api.x.ai/v1"
IMAGE_MODEL = "grok-imagine-image"
TTS_VOICE = "eve"
TTS_LANGUAGE = "en"

# PECS-style prompt: one clear concept, no text/letters in the image.
# The word label is rendered separately in the AAC app UI.
PECS_PROMPT_TEMPLATE = (
    "PECS AAC communication card symbol for a child: a simple, clear, "
    "photo-realistic icon of {word}. The subject fills about 85 percent of "
    "the frame, centered on a plain white background, with only a thin white "
    "margin. Tight crop, subject large in the frame. High contrast, easy to "
    "recognize at a glance, one single concept only. No text, no letters, no "
    "words, no labels, no watermark, no border frame, no collage, no multiple "
    "objects. Clean educational PECS-style symbol."
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


def load_xai_api_key() -> str:
    """Load XAI_API_KEY from env, falling back to credentials.env (never log it)."""
    key = os.environ.get("XAI_API_KEY", "").strip()
    if key:
        return key
    cred_path = Path.home() / ".config" / "xai" / "credentials.env"
    if cred_path.is_file():
        for line in cred_path.read_text().splitlines():
            line = line.strip()
            if line.startswith("XAI_API_KEY="):
                value = line.split("=", 1)[1].strip().strip('"').strip("'")
                if value:
                    os.environ["XAI_API_KEY"] = value
                    return value
    raise RuntimeError(
        "XAI_API_KEY not found. Set env or place it in ~/.config/xai/credentials.env"
    )


def slugify(word: str) -> str:
    s = word.strip().lower()
    s = re.sub(r"[^a-z0-9]+", "-", s)
    s = s.strip("-")
    return s or "card"


def pecs_prompt(word: str) -> str:
    return PECS_PROMPT_TEMPLATE.format(word=word.strip())


def meta_path(slug: str) -> Path:
    return DATA_DIR / slug / "meta.json"


def read_meta(slug: str) -> dict[str, Any] | None:
    p = meta_path(slug)
    if not p.is_file():
        return None
    return json.loads(p.read_text())


def write_meta(slug: str, meta: dict[str, Any]) -> None:
    p = meta_path(slug)
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(meta, indent=2) + "\n")


def public_urls(slug: str) -> dict[str, str]:
    return {
        "image_url": f"/assets/{slug}/image.png",
        "audio_url": f"/assets/{slug}/audio.mp3",
    }


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat()


def list_word_slugs() -> list[str]:
    if not DATA_DIR.is_dir():
        return []
    out: list[str] = []
    for child in sorted(DATA_DIR.iterdir()):
        if child.is_dir() and not child.name.startswith("_"):
            out.append(child.name)
    return out


def card_exists(slug: str) -> bool:
    return (DATA_DIR / slug).is_dir()


# ---------------------------------------------------------------------------
# Board persistence (folders + membership + root order)
# ---------------------------------------------------------------------------


def default_board() -> dict[str, Any]:
    return {
        "version": 1,
        "folders": {},
        "card_folder": {},  # word_slug -> folder_slug | null omitted
        "root_order": [],
    }


def atomic_write_json(path: Path, data: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_name = tempfile.mkstemp(prefix=".board-", suffix=".json", dir=str(path.parent))
    try:
        with os.fdopen(fd, "w") as f:
            json.dump(data, f, indent=2)
            f.write("\n")
        os.replace(tmp_name, path)
    except Exception:
        try:
            os.unlink(tmp_name)
        except OSError:
            pass
        raise


def load_board() -> dict[str, Any]:
    if not BOARD_PATH.is_file():
        return default_board()
    try:
        data = json.loads(BOARD_PATH.read_text())
    except (json.JSONDecodeError, OSError):
        return default_board()
    if not isinstance(data, dict):
        return default_board()
    data.setdefault("version", 1)
    data.setdefault("folders", {})
    data.setdefault("card_folder", {})
    data.setdefault("root_order", [])
    return data


def save_board(board: dict[str, Any]) -> None:
    atomic_write_json(BOARD_PATH, board)


def reconcile_board(board: dict[str, Any]) -> dict[str, Any]:
    """Ensure root_order / membership stay consistent with on-disk cards."""
    word_slugs = set(list_word_slugs())
    folders = board.get("folders") or {}
    card_folder = dict(board.get("card_folder") or {})
    root_order = list(board.get("root_order") or [])

    # Drop membership for missing cards / missing folders
    for slug, folder_id in list(card_folder.items()):
        if slug not in word_slugs or folder_id not in folders:
            card_folder.pop(slug, None)

    # Ensure each folder's children list only has existing cards; sync card_folder
    for fid, folder in folders.items():
        children = [c for c in (folder.get("children") or []) if c in word_slugs]
        # also pick up card_folder pointing here not yet listed
        for slug, parent in card_folder.items():
            if parent == fid and slug not in children:
                children.append(slug)
        folder["children"] = children
        for c in children:
            card_folder[c] = fid

    folder_slugs = set(folders.keys())
    # Items that belong on root: word cards without folder + all folders
    expected_root = set()
    for s in word_slugs:
        if s not in card_folder:
            expected_root.add(s)
    expected_root |= folder_slugs

    # Filter root_order to known items; append missing
    seen: set[str] = set()
    new_root: list[str] = []
    for s in root_order:
        if s in expected_root and s not in seen:
            new_root.append(s)
            seen.add(s)
    for s in sorted(expected_root - seen):
        # Prefer Food near front if newly added — keep alphabetical for others
        new_root.append(s)

    board["folders"] = folders
    board["card_folder"] = card_folder
    board["root_order"] = new_root
    return board


def ensure_seed_board() -> dict[str, Any]:
    """Seed Food folder with juice + ice-cream if those cards exist."""
    board = reconcile_board(load_board())
    changed = False

    food_slug = "food"
    if food_slug not in board["folders"]:
        board["folders"][food_slug] = {
            "name": "Food",
            "slug": food_slug,
            "kind": "folder",
            "image_url": FOLDER_IMAGE_URL,
            "created_at": utc_now(),
            "children": [],
        }
        if food_slug not in board["root_order"]:
            # Place Food near the front of root for caregiver UX
            board["root_order"] = [food_slug] + [
                s for s in board["root_order"] if s != food_slug
            ]
        changed = True

    food = board["folders"][food_slug]
    for child in ("juice", "ice-cream"):
        if card_exists(child):
            # remove from any other folder / root
            prev = board["card_folder"].get(child)
            if prev and prev in board["folders"] and prev != food_slug:
                kids = board["folders"][prev].get("children") or []
                board["folders"][prev]["children"] = [c for c in kids if c != child]
            board["card_folder"][child] = food_slug
            if child not in food["children"]:
                food["children"].append(child)
                changed = True
            # not on root
            if child in board["root_order"]:
                board["root_order"] = [s for s in board["root_order"] if s != child]
                changed = True

    board = reconcile_board(board)
    if changed or not BOARD_PATH.is_file():
        save_board(board)
    return board


def word_card_payload(slug: str, folder_id: str | None = None) -> dict[str, Any]:
    meta = read_meta(slug)
    if not meta:
        if not card_exists(slug):
            raise HTTPException(status_code=404, detail=f"card '{slug}' not found")
        meta = {"slug": slug, "word": slug}
        urls = public_urls(slug)
        meta.update(urls)
        img = DATA_DIR / slug / "image.png"
        aud = DATA_DIR / slug / "audio.mp3"
        if img.is_file():
            meta["image_path"] = str(img)
            meta["image_bytes"] = img.stat().st_size
        if aud.is_file():
            meta["audio_path"] = str(aud)
            meta["audio_bytes"] = aud.stat().st_size
    item = dict(meta)
    item["kind"] = "word"
    item["folder_id"] = folder_id
    return item


def folder_stub(folder: dict[str, Any]) -> dict[str, Any]:
    return {
        "kind": "folder",
        "word": folder.get("name") or folder.get("slug"),
        "slug": folder["slug"],
        "name": folder.get("name") or folder.get("slug"),
        "image_url": folder.get("image_url") or FOLDER_IMAGE_URL,
        "folder_id": None,
        "children": list(folder.get("children") or []),
        "created_at": folder.get("created_at"),
    }


# ---------------------------------------------------------------------------
# xAI clients
# ---------------------------------------------------------------------------


async def generate_image(client: httpx.AsyncClient, word: str, dest: Path) -> dict[str, Any]:
    """Call xAI image generations; download PNG promptly to dest."""
    api_key = load_xai_api_key()
    prompt = pecs_prompt(word)
    payload = {
        "model": IMAGE_MODEL,
        "prompt": prompt,
        "n": 1,
        "aspect_ratio": "1:1",
    }
    resp = await client.post(
        f"{XAI_BASE}/images/generations",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=120.0,
    )
    if resp.status_code >= 400:
        # Redact any accidental key leakage; return status + body snippet only.
        body = resp.text[:500]
        raise HTTPException(
            status_code=502,
            detail=f"xAI image API error {resp.status_code}: {body}",
        )
    data = resp.json()
    items = data.get("data") or data.get("images") or []
    if not items:
        raise HTTPException(status_code=502, detail="xAI image API returned no images")
    first = items[0]
    # Prefer URL download; fall back to b64_json if present.
    url = first.get("url")
    b64 = first.get("b64_json")
    dest.parent.mkdir(parents=True, exist_ok=True)
    if url:
        img_resp = await client.get(url, timeout=60.0)
        if img_resp.status_code >= 400:
            raise HTTPException(
                status_code=502,
                detail=f"Failed to download image URL: HTTP {img_resp.status_code}",
            )
        dest.write_bytes(img_resp.content)
    elif b64:
        import base64

        dest.write_bytes(base64.b64decode(b64))
    else:
        raise HTTPException(status_code=502, detail="Image response missing url and b64_json")
    # Crop the common "tiny subject on a huge white square" framing, then
    # re-pad to a thin consistent margin so the symbol fills the card cell.
    trim_and_pad_file(dest)
    return {"bytes": dest.stat().st_size, "prompt": prompt, "model": IMAGE_MODEL}


async def generate_tts(client: httpx.AsyncClient, word: str, dest: Path) -> dict[str, Any]:
    """Call xAI TTS; save MP3 to dest."""
    api_key = load_xai_api_key()
    payload = {
        "text": word.strip(),
        "voice_id": TTS_VOICE,
        "language": TTS_LANGUAGE,
    }
    resp = await client.post(
        f"{XAI_BASE}/tts",
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        json=payload,
        timeout=60.0,
    )
    if resp.status_code >= 400:
        body = resp.text[:500]
        raise HTTPException(
            status_code=502,
            detail=f"xAI TTS API error {resp.status_code}: {body}",
        )
    content_type = resp.headers.get("content-type", "")
    if "json" in content_type:
        # Some APIs return JSON with a URL; handle that.
        data = resp.json()
        url = data.get("url") or (data.get("audio") or {}).get("url")
        if url:
            audio_resp = await client.get(url, timeout=60.0)
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(audio_resp.content)
        else:
            raise HTTPException(status_code=502, detail="TTS JSON response missing audio url")
    else:
        dest.parent.mkdir(parents=True, exist_ok=True)
        dest.write_bytes(resp.content)
    return {"bytes": dest.stat().st_size, "voice_id": TTS_VOICE, "language": TTS_LANGUAGE}


# ---------------------------------------------------------------------------
# API models
# ---------------------------------------------------------------------------


class CreateCardRequest(BaseModel):
    word: str = Field(..., min_length=1, max_length=80, examples=["ice cream"])
    folder_id: str | None = Field(
        default=None,
        description="Parent folder slug, or null/omit for root",
    )


class CreateFolderRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=80, examples=["Food"])


class CardResponse(BaseModel):
    word: str
    slug: str
    image_path: str
    audio_path: str
    image_url: str
    audio_url: str
    created_at: str
    image_bytes: int | None = None
    audio_bytes: int | None = None
    kind: str = "word"
    folder_id: str | None = None


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------

app = FastAPI(
    title="Hope's Voice API",
    description="Generate PECS-style card assets (image + spoken word) via xAI.",
    version="0.2.0",
)


@app.on_event("startup")
async def _startup_seed() -> None:
    ensure_seed_board()


@app.get("/health")
async def health() -> dict[str, bool]:
    return {"ok": True}


@app.get("/v1/board")
async def get_board(
    request: Request,
    folder_id: str | None = Query(
        default=None,
        description="If set, return children of that folder; else root items",
    ),
) -> Response:
    """Board JSON with an ETag. Send `If-None-Match` to get `304` when nothing changed."""
    board = reconcile_board(load_board())
    folders = board["folders"]
    card_folder = board["card_folder"]

    if folder_id is not None:
        if folder_id not in folders:
            raise HTTPException(status_code=404, detail=f"folder '{folder_id}' not found")
        items: list[dict[str, Any]] = []
        for child_slug in folders[folder_id].get("children") or []:
            if card_exists(child_slug):
                items.append(word_card_payload(child_slug, folder_id=folder_id))
        return conditional_json(request, {"items": items, "folder_id": folder_id, "count": len(items)})

    items = []
    for slug in board["root_order"]:
        if slug in folders:
            items.append(folder_stub(folders[slug]))
        elif card_exists(slug):
            items.append(word_card_payload(slug, folder_id=card_folder.get(slug)))
    return conditional_json(request, {"items": items, "folder_id": None, "count": len(items)})


@app.post("/v1/folders")
async def create_folder(body: CreateFolderRequest) -> dict[str, Any]:
    name = body.name.strip()
    if not name:
        raise HTTPException(status_code=400, detail="name is required")
    slug = slugify(name)
    if card_exists(slug):
        raise HTTPException(
            status_code=409,
            detail=f"a word card with slug '{slug}' already exists",
        )
    board = reconcile_board(load_board())
    if slug in board["folders"]:
        # Idempotent: return existing
        return folder_stub(board["folders"][slug])

    folder = {
        "name": name,
        "slug": slug,
        "kind": "folder",
        "image_url": FOLDER_IMAGE_URL,
        "created_at": utc_now(),
        "children": [],
    }
    board["folders"][slug] = folder
    if slug not in board["root_order"]:
        board["root_order"].append(slug)
    save_board(board)
    return folder_stub(folder)


@app.delete("/v1/folders/{slug}")
async def delete_folder(slug: str) -> dict[str, Any]:
    board = reconcile_board(load_board())
    if slug not in board["folders"]:
        raise HTTPException(status_code=404, detail=f"folder '{slug}' not found")

    folder = board["folders"].pop(slug)
    children = list(folder.get("children") or [])

    # Move children to root (prefer)
    for child in children:
        board["card_folder"].pop(child, None)
        if child not in board["root_order"] and card_exists(child):
            board["root_order"].append(child)

    board["root_order"] = [s for s in board["root_order"] if s != slug]
    board = reconcile_board(board)
    save_board(board)
    return {
        "ok": True,
        "deleted": slug,
        "moved_to_root": [c for c in children if card_exists(c)],
    }


def _set_card_folder(board: dict[str, Any], slug: str, folder_id: str | None) -> None:
    """Assign word card to folder or root; update children lists."""
    # remove from previous folder
    prev = board["card_folder"].get(slug)
    if prev and prev in board["folders"]:
        kids = board["folders"][prev].get("children") or []
        board["folders"][prev]["children"] = [c for c in kids if c != slug]

    if folder_id:
        if folder_id not in board["folders"]:
            raise HTTPException(status_code=404, detail=f"folder '{folder_id}' not found")
        board["card_folder"][slug] = folder_id
        kids = board["folders"][folder_id].setdefault("children", [])
        if slug not in kids:
            kids.append(slug)
        board["root_order"] = [s for s in board["root_order"] if s != slug]
    else:
        board["card_folder"].pop(slug, None)
        if slug not in board["root_order"]:
            board["root_order"].append(slug)


@app.post("/v1/cards", response_model=CardResponse)
async def create_card(body: CreateCardRequest) -> CardResponse:
    word = body.word.strip()
    if not word:
        raise HTTPException(status_code=400, detail="word is required")
    slug = slugify(word)
    folder_id = body.folder_id.strip() if body.folder_id else None
    if folder_id == "":
        folder_id = None

    board = reconcile_board(load_board())
    if folder_id and folder_id not in board["folders"]:
        raise HTTPException(status_code=404, detail=f"folder '{folder_id}' not found")
    if slug in board["folders"]:
        raise HTTPException(
            status_code=409,
            detail=f"slug '{slug}' is already a folder",
        )

    card_dir = DATA_DIR / slug
    image_file = card_dir / "image.png"
    audio_file = card_dir / "audio.mp3"

    # Existing card: do not re-spend xAI; just update membership if requested
    if card_exists(slug) and image_file.is_file() and audio_file.is_file():
        meta = read_meta(slug) or {}
        urls = public_urls(slug)
        meta.setdefault("word", word)
        meta.setdefault("slug", slug)
        meta.setdefault("image_path", str(image_file))
        meta.setdefault("audio_path", str(audio_file))
        meta.setdefault("image_url", urls["image_url"])
        meta.setdefault("audio_url", urls["audio_url"])
        meta.setdefault("created_at", utc_now())
        write_meta(slug, meta)
        _set_card_folder(board, slug, folder_id)
        save_board(reconcile_board(board))
        return CardResponse(
            word=meta["word"],
            slug=slug,
            image_path=meta["image_path"],
            audio_path=meta["audio_path"],
            image_url=meta["image_url"],
            audio_url=meta["audio_url"],
            created_at=meta["created_at"],
            image_bytes=meta.get("image_bytes"),
            audio_bytes=meta.get("audio_bytes"),
            kind="word",
            folder_id=folder_id,
        )

    async with httpx.AsyncClient() as client:
        img_info = await generate_image(client, word, image_file)
        tts_info = await generate_tts(client, word, audio_file)

    now = utc_now()
    urls = public_urls(slug)
    meta = {
        "word": word,
        "slug": slug,
        "image_path": str(image_file),
        "audio_path": str(audio_file),
        "image_url": urls["image_url"],
        "audio_url": urls["audio_url"],
        "created_at": now,
        "image_bytes": img_info["bytes"],
        "audio_bytes": tts_info["bytes"],
        "image_model": img_info["model"],
        "tts_voice": tts_info["voice_id"],
        "prompt": img_info["prompt"],
    }
    write_meta(slug, meta)

    _set_card_folder(board, slug, folder_id)
    save_board(reconcile_board(board))

    return CardResponse(
        word=meta["word"],
        slug=slug,
        image_path=meta["image_path"],
        audio_path=meta["audio_path"],
        image_url=meta["image_url"],
        audio_url=meta["audio_url"],
        created_at=meta["created_at"],
        image_bytes=meta["image_bytes"],
        audio_bytes=meta["audio_bytes"],
        kind="word",
        folder_id=folder_id,
    )


@app.get("/v1/cards")
async def list_cards(request: Request) -> Response:
    """Flat list of word cards only (backward compatible for old clients)."""
    board = reconcile_board(load_board())
    card_folder = board.get("card_folder") or {}
    cards: list[dict[str, Any]] = []
    if DATA_DIR.is_dir():
        for child in sorted(DATA_DIR.iterdir()):
            if not child.is_dir() or child.name.startswith("_"):
                continue
            meta = read_meta(child.name)
            if meta:
                item = dict(meta)
            else:
                item = {"slug": child.name, "word": child.name}
            item["kind"] = "word"
            item["folder_id"] = card_folder.get(child.name)
            cards.append(item)
    return conditional_json(request, {"cards": cards, "count": len(cards)})


@app.get("/v1/cards/{slug}")
async def get_card(slug: str) -> dict[str, Any]:
    board = reconcile_board(load_board())
    if slug in board["folders"]:
        return folder_stub(board["folders"][slug])
    folder_id = board["card_folder"].get(slug)
    return word_card_payload(slug, folder_id=folder_id)


@app.delete("/v1/cards/{slug}")
async def delete_card(slug: str) -> dict[str, Any]:
    board = reconcile_board(load_board())
    if slug in board["folders"]:
        raise HTTPException(
            status_code=400,
            detail=f"'{slug}' is a folder; use DELETE /v1/folders/{slug}",
        )
    card_dir = DATA_DIR / slug
    if not card_dir.is_dir():
        raise HTTPException(status_code=404, detail=f"card '{slug}' not found")

    # Remove from board membership
    prev = board["card_folder"].pop(slug, None)
    if prev and prev in board["folders"]:
        kids = board["folders"][prev].get("children") or []
        board["folders"][prev]["children"] = [c for c in kids if c != slug]
    board["root_order"] = [s for s in board["root_order"] if s != slug]

    shutil.rmtree(card_dir)
    save_board(reconcile_board(board))
    return {"ok": True, "deleted": slug}


app.include_router(sync_router)

# Static assets: /assets/<slug>/image.png etc.
app.mount("/assets", StaticFiles(directory=str(DATA_DIR)), name="assets")
app.mount("/system", StaticFiles(directory=str(SYSTEM_DIR)), name="system")
