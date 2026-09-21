"""Optional API-key protection.

Authentication is intentionally kept minimal: MATLAB has none, and the bridge
does not invent an identity system. When JEEVANA_API_KEY is set, every /api/*
route requires it via the X-API-Key header. When it is empty, the API is open
(and CORS controls browser access). The dependency pattern makes it trivial to
swap for OAuth2/JWT later.
"""

from __future__ import annotations

import secrets

from fastapi import Header, HTTPException

from .config import settings

_HEADER_NAME = "x-api-key"


def require_api_key(x_api_key: str | None = Header(default=None, alias="X-API-Key")) -> None:
    if not settings.api_key:
        return
    if not x_api_key:
        raise HTTPException(status_code=401, detail="API key required.")
    if not secrets.compare_digest(x_api_key.encode("utf-8"), settings.api_key.encode("utf-8")):
        raise HTTPException(status_code=401, detail="Invalid API key.")