"""Conditional GET helpers (ETag / If-None-Match) for read-only JSON routes.

Clients keep the last response on disk and send `If-None-Match`. When nothing changed the
server answers `304 Not Modified` with no body, so a refresh costs one tiny round trip and the
app never has to wait on a full board download.
"""

from __future__ import annotations

import hashlib
import json
from typing import Any

from fastapi import Request, Response
from fastapi.responses import JSONResponse

# `no-cache` means "store it, but always revalidate": the app (and Cloudflare, if it ever
# caches this route) must ask before reusing it. 304s keep that cheap.
CACHE_CONTROL = "no-cache"


def compute_etag(payload: Any) -> str:
    """Strong validator derived from the canonical JSON of the payload."""
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), ensure_ascii=False)
    digest = hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:32]
    return f'"{digest}"'


def _opaque_tag(token: str) -> str:
    token = token.strip()
    if token.startswith("W/"):
        token = token[2:]
    return token


def etag_matches(if_none_match: str | None, etag: str) -> bool:
    """True when an `If-None-Match` header lists `etag` (weak comparison) or is `*`."""
    if not if_none_match:
        return False
    if if_none_match.strip() == "*":
        return True
    wanted = _opaque_tag(etag)
    return any(_opaque_tag(part) == wanted for part in if_none_match.split(","))


def conditional_json(request: Request, payload: Any) -> Response:
    """200 JSON with an ETag, or 304 when the caller already has this exact version."""
    etag = compute_etag(payload)
    headers = {"ETag": etag, "Cache-Control": CACHE_CONTROL}
    if etag_matches(request.headers.get("if-none-match"), etag):
        return Response(status_code=304, headers=headers)
    return JSONResponse(payload, headers=headers)
