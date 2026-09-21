"""POST /api/screen — real MATLAB screening of an uploaded retinal image.

Accepts multipart/form-data with a file field named `image` (PNG or JPEG).
The bridge validates the payload, hands the raw image bytes to the compiled
MATLAB pipeline and returns the genuine screening result.
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, File, Query, UploadFile
from fastapi.responses import JSONResponse

from ..config import settings
from ..errors import ApiError, MatlabExecutionError, MatlabNotConfiguredError
from ..security import require_api_key
from ..services.factory import get_matlab_service
from ..utils import images

logger = logging.getLogger("jeevana.api.screen")
router = APIRouter(dependencies=[Depends(require_api_key)])


@router.post("/api/screen", tags=["screening"])
async def screen_image(
    image: UploadFile = File(..., description="PNG or JPEG retinal fundus image"),
    includeEvidence: bool = Query(default=True, description="Run lesion evidence extraction"),
) -> JSONResponse:
    # Validate the client request first so malformed input yields 4xx even
    # when MATLAB is not configured.
    data = await read_limited(image)
    try:
        images.validate_image(data)
    except ValueError as exc:
        raise ApiError(400, str(exc)) from exc

    service = get_matlab_service()
    if service is None:
        raise MatlabNotConfiguredError()

    try:
        screening = await _run(service, data, includeEvidence)
    except MatlabExecutionError as exc:
        logger.error("MATLAB screen failed: %s", exc.message)
        raise ApiError(503, "MATLAB screening service failed.") from exc

    return JSONResponse(content=screening)


async def read_limited(upload: UploadFile) -> bytes:
    max_bytes = settings.max_upload_mb * 1024 * 1024
    data = await upload.read(max_bytes + 1)
    if len(data) > max_bytes:
        raise ApiError(400, f"Uploaded image exceeds the {settings.max_upload_mb} MB limit.")
    return data


async def _run(service, data: bytes, include_evidence: bool) -> dict:
    # Run CPU-bound MATLAB work off the event loop so the process stays
    # responsive while the compiled model executes.
    import anyio

    return await anyio.to_thread.run_sync(lambda: service.screen(data, include_evidence))