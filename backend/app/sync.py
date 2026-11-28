"""Remote board sync: versioned per-profile documents behind bearer tokens.

A profile document (`bestwishes.sync/v1`) holds what a caregiver can edit on a
device: the imported board (optional), the local overlays (hide, order, labels,
positions, spoken text, colors) and a map of caregiver photos to content
hashes. Every accepted change is a new immutable version, so history is
browsable and any version can be restored (as a new version on top).

Auth (nothing here is anonymous):
- `HOPESVOICE_ADMIN_TOKEN` env var: full access, mints device tokens.
- Device tokens are minted by an admin, shown once, and stored only as a
  SHA-256 hash. Scope `read` can fetch; `write` can also push edits, upload
  pictures and roll back.

Caching: GET responses carry `ETag: "<version>"` and honour `If-None-Match`
(304). Blobs are content-addressed (`sha256`), so they never change.
"""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, Request, Response
from pydantic import BaseModel, Field

from app import main_paths
from app.board_import import validate as validate_board

SYNC_FORMAT = "bestwishes.sync/v1"
PROFILE_ID_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,39}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
MAX_DOC_BYTES = 4 * 1024 * 1024
MAX_BLOB_BYTES = 8 * 1024 * 1024
OVERLAY_KEYS = ("hidden", "order", "labels", "positions", "speak", "styles")
SCOPES = {"read": 1, "write": 2, "admin": 3}

router = APIRouter(prefix="/v1/sync", tags=["sync"])


# ---------------------------------------------------------------------------
# Storage
# ---------------------------------------------------------------------------


def sync_root() -> Path:
    root = main_paths.data_root() / "sync"
    root.mkdir(parents=True, exist_ok=True)
    return root


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _atomic_write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=path.parent, prefix=".tmp-")
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(data)
        os.replace(tmp, path)
    except Exception:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def _profile_dir(profile_id: str) -> Path:
    if not PROFILE_ID_RE.match(profile_id):
        raise HTTPException(status_code=400, detail="profile id must be lowercase letters, digits and dashes")
    return sync_root() / "profiles" / profile_id


def _version_path(profile_id: str, version: int) -> Path:
    return _profile_dir(profile_id) / f"v{version:06d}.json"


def head_version(profile_id: str) -> int:
    folder = _profile_dir(profile_id)
    if not folder.is_dir():
        return 0
    versions = [int(p.stem[1:]) for p in folder.glob("v??????.json")]
    return max(versions) if versions else 0


def read_version(profile_id: str, version: int) -> dict[str, Any] | None:
    path = _version_path(profile_id, version)
    if not path.is_file():
        return None
    return json.loads(path.read_text())


def _canonical(doc: Any) -> str:
    return json.dumps(doc, sort_keys=True, separators=(",", ":"))


def write_version(profile_id: str, doc: dict[str, Any], author: str, note: str) -> dict[str, Any]:
    version = head_version(profile_id) + 1
    record = {
        "profile_id": profile_id,
        "version": version,
        "updated_at": _now(),
        "author": author,
        "note": note,
        "doc": doc,
    }
    _atomic_write(_version_path(profile_id, version), json.dumps(record, indent=1, sort_keys=True).encode())
    return record


def list_profile_ids() -> list[str]:
    base = sync_root() / "profiles"
    if not base.is_dir():
        return []
    return sorted(p.name for p in base.iterdir() if p.is_dir() and PROFILE_ID_RE.match(p.name))


# ---------------------------------------------------------------------------
# Document validation
# ---------------------------------------------------------------------------


def empty_doc() -> dict[str, Any]:
    return {
        "format": SYNC_FORMAT,
        "board": None,
        "overlays": {
            "hidden": [],
            "order": {},
            "labels": {},
            "positions": {},
            "speak": {},
            "styles": {},
        },
        "images": {},
    }


def validate_doc(doc: Any) -> list[str]:
    """Return every problem found; an empty list means the document is storable."""
    errors: list[str] = []
    if not isinstance(doc, dict):
        return ["document must be an object"]
    if doc.get("format") != SYNC_FORMAT:
        errors.append(f'format must be "{SYNC_FORMAT}"')
    board = doc.get("board")
    if board is not None:
        if not isinstance(board, dict):
            errors.append("board must be an object or null")
        else:
            errors.extend(f"board: {e}" for e in validate_board(board))
    overlays = doc.get("overlays")
    if not isinstance(overlays, dict):
        errors.append("overlays must be an object")
        overlays = {}
    hidden = overlays.get("hidden", [])
    if not isinstance(hidden, list) or not all(isinstance(x, str) for x in hidden):
        errors.append("overlays.hidden must be a list of strings")
    order = overlays.get("order", {})
    if not isinstance(order, dict) or not all(
        isinstance(v, list) and all(isinstance(x, str) for x in v) for v in order.values()
    ):
        errors.append("overlays.order must map board keys to lists of ids")
    for key in ("labels", "speak"):
        value = overlays.get(key, {})
        if not isinstance(value, dict) or not all(isinstance(v, str) for v in value.values()):
            errors.append(f"overlays.{key} must map ids to strings")
    positions = overlays.get("positions", {})
    if not isinstance(positions, dict) or not all(
        isinstance(m, dict) and all(_is_coord(c) for c in m.values()) for m in positions.values()
    ):
        errors.append("overlays.positions must map board keys to {id: {row, col}}")
    styles = overlays.get("styles", {})
    if not isinstance(styles, dict) or not all(
        isinstance(s, dict) and all(isinstance(v, str) for v in s.values()) for s in styles.values()
    ):
        errors.append("overlays.styles must map ids to {backgroundHex, borderHex}")
    images = doc.get("images", {})
    if not isinstance(images, dict) or not all(
        isinstance(k, str) and isinstance(v, str) and SHA_RE.match(v) for k, v in images.items()
    ):
        errors.append("images must map ids to sha256 hex digests")
    extra = set(doc) - {"format", "board", "overlays", "images"}
    if extra:
        errors.append(f"unknown top-level keys: {sorted(extra)}")
    return errors


def _is_coord(value: Any) -> bool:
    return (
        isinstance(value, dict)
        and isinstance(value.get("row"), int)
        and isinstance(value.get("col"), int)
        and not isinstance(value.get("row"), bool)
        and not isinstance(value.get("col"), bool)
    )


def normalise_doc(doc: dict[str, Any]) -> dict[str, Any]:
    """Fill defaults so every stored document has the same shape."""
    base = empty_doc()
    overlays = dict(base["overlays"])
    overlays.update(doc.get("overlays") or {})
    overlays["hidden"] = sorted(set(overlays.get("hidden") or []))
    return {
        "format": SYNC_FORMAT,
        "board": doc.get("board"),
        "overlays": overlays,
        "images": dict(doc.get("images") or {}),
    }


# ---------------------------------------------------------------------------
# Auth
# ---------------------------------------------------------------------------


class Principal(BaseModel):
    name: str
    scope: str


def _tokens_path() -> Path:
    return sync_root() / "tokens.json"


def _load_tokens() -> dict[str, Any]:
    path = _tokens_path()
    if not path.is_file():
        return {}
    return json.loads(path.read_text())


def _hash_token(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def authenticate(request: Request) -> Principal:
    header = request.headers.get("authorization", "")
    scheme, _, token = header.partition(" ")
    token = token.strip()
    if scheme.lower() != "bearer" or not token:
        raise HTTPException(status_code=401, detail="bearer token required", headers={"WWW-Authenticate": "Bearer"})
    admin = os.environ.get("HOPESVOICE_ADMIN_TOKEN", "").strip()
    if admin and hmac.compare_digest(_hash_token(token), _hash_token(admin)):
        return Principal(name="admin", scope="admin")
    digest = _hash_token(token)
    for record in _load_tokens().values():
        if hmac.compare_digest(record["sha256"], digest):
            return Principal(name=record["name"], scope=record["scope"])
    raise HTTPException(status_code=401, detail="invalid token", headers={"WWW-Authenticate": "Bearer"})


def require(scope: str):
    def dependency(principal: Principal = Depends(authenticate)) -> Principal:
        if SCOPES[principal.scope] < SCOPES[scope]:
            raise HTTPException(status_code=403, detail=f"{scope} scope required")
        return principal

    return dependency


class CreateTokenRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=60)
    scope: str = Field("write", pattern="^(read|write)$")


@router.post("/tokens")
async def create_token(body: CreateTokenRequest, _: Principal = Depends(require("admin"))) -> dict[str, Any]:
    token = "hv_" + secrets.token_urlsafe(32)
    tokens = _load_tokens()
    token_id = secrets.token_hex(4)
    tokens[token_id] = {
        "name": body.name,
        "scope": body.scope,
        "sha256": _hash_token(token),
        "created_at": _now(),
    }
    _atomic_write(_tokens_path(), json.dumps(tokens, indent=1).encode())
    return {"id": token_id, "name": body.name, "scope": body.scope, "token": token}


@router.get("/tokens")
async def list_tokens(_: Principal = Depends(require("admin"))) -> dict[str, Any]:
    return {
        "tokens": [
            {"id": tid, "name": r["name"], "scope": r["scope"], "created_at": r["created_at"]}
            for tid, r in sorted(_load_tokens().items())
        ]
    }


@router.delete("/tokens/{token_id}")
async def revoke_token(token_id: str, _: Principal = Depends(require("admin"))) -> dict[str, Any]:
    tokens = _load_tokens()
    if token_id not in tokens:
        raise HTTPException(status_code=404, detail="token not found")
    del tokens[token_id]
    _atomic_write(_tokens_path(), json.dumps(tokens, indent=1).encode())
    return {"ok": True, "revoked": token_id}


# ---------------------------------------------------------------------------
# Profiles
# ---------------------------------------------------------------------------


def _etag(version: int) -> str:
    return f'"{version}"'


def _parse_etag(raw: str | None) -> int | None:
    if raw is None:
        return None
    raw = raw.strip()
    if raw.startswith("W/"):
        raw = raw[2:]
    raw = raw.strip('"')
    return int(raw) if raw.isdigit() else None


def _summary(record: dict[str, Any]) -> dict[str, Any]:
    return {k: record[k] for k in ("profile_id", "version", "updated_at", "author", "note")}


@router.get("/profiles")
async def list_profiles(request: Request, response: Response, _: Principal = Depends(require("read"))):
    """One cheap request tells a device which profiles changed."""
    items = []
    for pid in list_profile_ids():
        version = head_version(pid)
        if version:
            record = read_version(pid, version)
            if record:
                items.append(_summary(record))
    tag = '"m-' + hashlib.sha256(_canonical(items).encode()).hexdigest()[:16] + '"'
    if request.headers.get("if-none-match") == tag:
        return Response(status_code=304, headers={"ETag": tag})
    response.headers["ETag"] = tag
    return {"profiles": items}


@router.get("/profiles/{profile_id}")
async def get_profile(profile_id: str, request: Request, _: Principal = Depends(require("read"))):
    version = head_version(profile_id)
    if not version:
        raise HTTPException(status_code=404, detail="profile has no synced board yet")
    if _parse_etag(request.headers.get("if-none-match")) == version:
        return Response(status_code=304, headers={"ETag": _etag(version)})
    record = read_version(profile_id, version)
    return _json(record, headers={"ETag": _etag(version)})


def _json(payload: Any, status: int = 200, headers: dict[str, str] | None = None) -> Response:
    return Response(
        content=json.dumps(payload),
        status_code=status,
        media_type="application/json",
        headers=headers or {},
    )


class PutProfileRequest(BaseModel):
    doc: dict[str, Any]
    note: str = Field("", max_length=200)


def _store(profile_id: str, doc: dict[str, Any], expected: int | None, principal: Principal, note: str) -> Response:
    """Optimistic-concurrency write shared by PUT, ops and rollback."""
    errors = validate_doc(doc)
    if errors:
        raise HTTPException(status_code=422, detail={"errors": errors})
    doc = normalise_doc(doc)
    if len(json.dumps(doc)) > MAX_DOC_BYTES:
        raise HTTPException(status_code=413, detail="document too large")
    current = head_version(profile_id)
    if expected is not None and expected != current:
        return _json(
            {"detail": "version conflict", "current_version": current},
            status=412,
            headers={"ETag": _etag(current)},
        )
    if current:
        head = read_version(profile_id, current)
        if head and _canonical(head["doc"]) == _canonical(doc):
            return _json(head, headers={"ETag": _etag(current)})
    record = write_version(profile_id, doc, principal.name, note)
    return _json(record, status=200, headers={"ETag": _etag(record["version"])})


@router.put("/profiles/{profile_id}")
async def put_profile(
    profile_id: str,
    body: PutProfileRequest,
    request: Request,
    principal: Principal = Depends(require("write")),
):
    raw = request.headers.get("if-match")
    expected = _parse_etag(raw)
    if expected is None:
        raise HTTPException(status_code=428, detail='If-Match required: the version you last saw ("0" to create)')
    return _store(profile_id, body.doc, expected, principal, body.note)


@router.get("/profiles/{profile_id}/versions")
async def list_versions(profile_id: str, _: Principal = Depends(require("read"))) -> dict[str, Any]:
    head = head_version(profile_id)
    if not head:
        raise HTTPException(status_code=404, detail="profile has no synced board yet")
    versions = []
    for n in range(head, 0, -1):
        record = read_version(profile_id, n)
        if record:
            versions.append(_summary(record))
    return {"profile_id": profile_id, "head": head, "versions": versions}


@router.get("/profiles/{profile_id}/versions/{version}")
async def get_version(profile_id: str, version: int, _: Principal = Depends(require("read"))):
    record = read_version(profile_id, version)
    if not record:
        raise HTTPException(status_code=404, detail="version not found")
    return _json(record, headers={"ETag": _etag(version)})


class RollbackRequest(BaseModel):
    to_version: int = Field(..., ge=1)


@router.post("/profiles/{profile_id}/rollback")
async def rollback(
    profile_id: str,
    body: RollbackRequest,
    principal: Principal = Depends(require("write")),
):
    """Restore an older version by writing it again as the newest version."""
    old = read_version(profile_id, body.to_version)
    if not old:
        raise HTTPException(status_code=404, detail="version not found")
    return _store(profile_id, old["doc"], None, principal, f"rollback to v{body.to_version}")


# ---------------------------------------------------------------------------
# Edit operations (used by the CLI and trusted bots)
# ---------------------------------------------------------------------------


class OpsRequest(BaseModel):
    ops: list[dict[str, Any]] = Field(..., min_length=1, max_length=100)
    base_version: int | None = None
    note: str = Field("", max_length=200)


def _find_board(doc: dict[str, Any], board_id: str | None) -> dict[str, Any]:
    board = doc.get("board")
    if not board:
        raise ValueError("this profile has no imported board; board ops need one")
    wanted = board_id or (board.get("profile") or {}).get("homeBoard")
    for candidate in board.get("boards", []):
        if candidate.get("id") == wanted:
            return candidate
    raise ValueError(f'board "{wanted}" not found')


def _find_cell(board: dict[str, Any], cell_id: str) -> dict[str, Any]:
    for cell in board.get("cells", []):
        if cell.get("id") == cell_id:
            return cell
    raise ValueError(f'cell "{cell_id}" not found')


def apply_op(doc: dict[str, Any], op: dict[str, Any]) -> None:
    """Mutate `doc` for one edit. Raises ValueError with a readable message."""
    kind = op.get("op")
    overlays = doc["overlays"]
    if kind in ("set_label", "set_speak"):
        key = "labels" if kind == "set_label" else "speak"
        target = str(op.get("id") or "").strip()
        text = str(op.get("text") if op.get("text") is not None else op.get("label", "")).strip()
        if not target:
            raise ValueError(f"{kind} needs id")
        if text:
            overlays[key][target] = text
        else:
            overlays[key].pop(target, None)
    elif kind in ("hide", "unhide"):
        target = str(op.get("id") or "").strip()
        if not target:
            raise ValueError(f"{kind} needs id")
        hidden = set(overlays["hidden"])
        (hidden.add if kind == "hide" else hidden.discard)(target)
        overlays["hidden"] = sorted(hidden)
    elif kind == "set_style":
        target = str(op.get("id") or "").strip()
        if not target:
            raise ValueError("set_style needs id")
        style = dict(overlays["styles"].get(target) or {"backgroundHex": "FCFCF7", "borderHex": "1C1A17"})
        if op.get("background"):
            style["backgroundHex"] = str(op["background"]).lstrip("#").upper()
        if op.get("border"):
            style["borderHex"] = str(op["border"]).lstrip("#").upper()
        overlays["styles"][target] = style
    elif kind == "move":
        key = str(op.get("board_key", ""))
        overlays["positions"].setdefault(key, {})[str(op["id"])] = {"row": int(op["row"]), "col": int(op["col"])}
    elif kind == "move_cell":
        board = _find_board(doc, op.get("board"))
        cell = _find_cell(board, str(op["cell"]))
        cell["row"], cell["col"] = int(op["row"]), int(op["col"])
    elif kind == "set_cell":
        board = _find_board(doc, op.get("board"))
        cell = _find_cell(board, str(op["cell"]))
        for field in ("label", "speak", "bg", "border", "pos"):
            if field in op:
                cell[field] = op[field]
        if "hidden" in op:
            cell["hidden"] = bool(op["hidden"])
    elif kind == "add_button":
        board = _find_board(doc, op.get("board"))
        cell = dict(op["cell"])
        cell.setdefault("type", "word")
        board.setdefault("cells", []).append(cell)
    elif kind == "add_folder":
        parent = _find_board(doc, op.get("board"))
        new_id = str(op["id"])
        title = str(op.get("title") or op.get("label") or new_id)
        doc["board"]["boards"].append({"id": new_id, "title": title, "cells": []})
        parent.setdefault("cells", []).append(
            {
                "id": f"folder-{new_id}",
                "type": "folder",
                "label": title,
                "target": new_id,
                "row": int(op["row"]),
                "col": int(op["col"]),
            }
        )
    elif kind == "remove_button":
        board = _find_board(doc, op.get("board"))
        cell_id = str(op["cell"])
        _find_cell(board, cell_id)
        board["cells"] = [c for c in board["cells"] if c.get("id") != cell_id]
    else:
        raise ValueError(f"unknown op {kind!r}")


@router.post("/profiles/{profile_id}/ops")
async def apply_ops(
    profile_id: str,
    body: OpsRequest,
    principal: Principal = Depends(require("write")),
):
    """Apply edits to the newest version and store the result as one new version."""
    current = head_version(profile_id)
    if body.base_version is not None and body.base_version != current:
        return _json(
            {"detail": "version conflict", "current_version": current},
            status=412,
            headers={"ETag": _etag(current)},
        )
    doc = normalise_doc(read_version(profile_id, current)["doc"]) if current else empty_doc()
    try:
        for op in body.ops:
            apply_op(doc, op)
    except (ValueError, KeyError, TypeError) as exc:
        raise HTTPException(status_code=422, detail={"errors": [f"{type(exc).__name__}: {exc}"]})
    note = body.note or ", ".join(str(o.get("op")) for o in body.ops)[:200]
    return _store(profile_id, doc, current, principal, note)


# ---------------------------------------------------------------------------
# Pictures (content-addressed)
# ---------------------------------------------------------------------------


def _blob_path(sha: str) -> Path:
    if not SHA_RE.match(sha):
        raise HTTPException(status_code=400, detail="blob id must be a sha256 hex digest")
    return sync_root() / "blobs" / sha[:2] / sha


@router.put("/blobs/{sha}")
async def put_blob(sha: str, request: Request, _: Principal = Depends(require("write"))) -> dict[str, Any]:
    path = _blob_path(sha)
    declared = request.headers.get("content-length")
    if declared and declared.isdigit() and int(declared) > MAX_BLOB_BYTES:
        raise HTTPException(status_code=413, detail="picture too large")
    data = await request.body()
    if len(data) > MAX_BLOB_BYTES:
        raise HTTPException(status_code=413, detail="picture too large")
    if hashlib.sha256(data).hexdigest() != sha:
        raise HTTPException(status_code=422, detail="body does not match the sha256 in the URL")
    if not path.is_file():
        _atomic_write(path, data)
    return {"ok": True, "sha256": sha, "bytes": len(data)}


@router.head("/blobs/{sha}")
async def head_blob(sha: str, _: Principal = Depends(require("read"))) -> Response:
    path = _blob_path(sha)
    if not path.is_file():
        return Response(status_code=404)
    return Response(status_code=200, headers={"Content-Length": str(path.stat().st_size)})


@router.get("/blobs/{sha}")
async def get_blob(sha: str, _: Principal = Depends(require("read"))) -> Response:
    path = _blob_path(sha)
    if not path.is_file():
        raise HTTPException(status_code=404, detail="picture not found")
    return Response(
        content=path.read_bytes(),
        media_type="image/png",
        headers={"ETag": f'"{sha}"', "Cache-Control": "private, max-age=31536000, immutable"},
    )
