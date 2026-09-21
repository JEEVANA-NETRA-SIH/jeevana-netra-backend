"""Image upload validation.

Images are sniffed by magic bytes, never trusted from file names or client
declared content types. Uploaded bytes are processed in memory and only ever
temporarily materialized inside the MATLAB CLI working directory, which is
created and removed by the service layer.
"""

from __future__ import annotations

_PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"
_JPEG_SIGNATURES = (b"\xff\xd8\xff\xe0", b"\xff\xd8\xff\xe1", b"\xff\xd8\xff")

SUPPORTED_FORMATS = {"png": "image/png", "jpeg": "image/jpeg"}

# Signatures do not depend on filename: "veto" by content only.
FORBIDDEN_EXTENSIONS: set[str] = set()


def sniff_image(data: bytes) -> str | None:
    """Return 'png' or 'jpeg' when magic bytes match, else None."""
    if data[:8] == _PNG_SIGNATURE:
        return "png"
    for sig in _JPEG_SIGNATURES:
        if data.startswith(sig):
            return "jpeg"
    return None


def validate_image(data: bytes) -> str:
    """Raise ValueError for non-image payloads; return the format name."""
    if not data:
        raise ValueError("Uploaded image is empty.")
    kind = sniff_image(data)
    if kind is None:
        raise ValueError("Uploaded file is not a PNG or JPEG image.")
    return kind


def check_allowed_size(data: bytes, max_mb: int) -> int:
    """Return len(data), raising ValueError when the payload exceeds max_mb."""
    limit = max_mb * 1024 * 1024
    if len(data) > limit:
        raise ValueError(f"Uploaded image exceeds the {max_mb} MB limit.")
    return len(data)