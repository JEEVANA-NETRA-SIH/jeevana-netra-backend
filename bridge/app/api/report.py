"""POST /api/report — real MATLAB PDF report generation.

Contract:
  - application/json  : { patient, result, screeningId?, imageBase64 }
  - multipart/form-data : image (file) + patient (JSON) + result (JSON)

Response: application/pdf by default; JSON {base64} when ?format=base64.
"""

from __future__ import annotations

import base64
import json
import logging
import re

from fastapi import APIRouter, Depends, Query, Request
from fastapi.responses import JSONResponse, Response
from pydantic import ValidationError

from ..config import settings
from ..errors import ApiError, MatlabExecutionError, MatlabNotConfiguredError
from ..schemas import ReportRequestIn
from ..security import require_api_key
from ..services.factory import get_matlab_service
from ..utils import images

logger = logging.getLogger("jeevana.api.report")
router = APIRouter(dependencies=[Depends(require_api_key)])


def _payload_size_limit() -> int:
    """Cap the total request body: base64 inflates an image by ~4/3, and
    multipart adds form overhead. Budget extra room so a max-size image still
    fits while any larger body is rejected before it is parsed."""
    base = max(settings.max_upload_mb, 1) * 1024 * 1024
    return int(base * 4 / 3) + (2 * 1024 * 1024)


def _reject_oversized_body(request: Request) -> None:
    content_length = request.headers.get("content-length")
    if content_length is None:
        return
    try:
        total = int(content_length)
    except ValueError:
        return
    if total > _payload_size_limit():
        raise ApiError(
            400,
            f"Request payload too large (limit {settings.max_upload_mb} MB image).",
        )


def _safe_report_filename(value: str) -> str:
    clean = re.sub(r'[\r\n"\x00]', "", str(value)).strip()
    return clean or "Jeevana_Netra_Report.pdf"


@router.post("/api/report", tags=["report"], response_model=None)
async def report_generate(
    request: Request,
    format_: str | None = Query(default=None, alias="format"),
) -> Response | JSONResponse:
    # Parse and validate the request before checking MATLAB so malformed
    # requests return 4xx rather than 503.
    content_type = request.headers.get("content-type", "").lower()
    _reject_oversized_body(request)

    if content_type.startswith("multipart/form-data"):
        payload = await _parse_multipart(request)
    elif content_type.startswith("application/json"):
        payload = await _parse_json(request)
    else:
        raise ApiError(
            415,
            "Send application/json or multipart/form-data.",
        )

    service = get_matlab_service()
    if service is None:
        raise MatlabNotConfiguredError()

    try:
        import anyio

        matlab_out = await anyio.to_thread.run_sync(
            lambda: service.generate_report(payload)
        )
    except MatlabExecutionError as exc:
        logger.error("MATLAB report failed: %s", exc.message)
        raise ApiError(503, "MATLAB report service failed.") from exc

    filename = _safe_report_filename(matlab_out.get("filename", "Jeevana_Netra_Report.pdf"))
    pdf_bytes = _extract_pdf_bytes(matlab_out)

    if format_ in ("base64", "json"):
        return JSONResponse(
            content={
                "status": "success",
                "filename": filename,
                "sizeBytes": len(pdf_bytes),
                "pdfBase64": base64.b64encode(pdf_bytes).decode("ascii"),
            }
        )

    return Response(
        content=pdf_bytes,
        media_type="application/pdf",
        headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
        },
    )


async def _parse_json(request: Request) -> dict:
    try:
        raw = await request.json()
    except ValueError as exc:
        raise ApiError(422, "Request body is not valid JSON.") from exc
    try:
        model = ReportRequestIn.model_validate(raw)
    except ValidationError as exc:
        raise ApiError(422, "Invalid report request data.") from exc

    image_bytes = decode_base64(model.imageBase64)
    try:
        images.validate_image(image_bytes)
        images.check_allowed_size(image_bytes, settings.max_upload_mb)
    except ValueError as exc:
        raise ApiError(400, str(exc)) from exc

    return build_matlab_request(
        patient=model.patient.model_dump(),
        result=model.result.model_dump(),
        screeningId=model.screeningId,
        image_bytes=image_bytes,
    )


async def _parse_multipart(request: Request) -> dict:
    form = await request.form()
    image_file = form.get("image")
    patient_raw = form.get("patient")
    result_raw = form.get("result")
    screening_id = form.get("screeningId")

    if image_file is None:
        raise ApiError(422, "multipart report requires an image file field.")
    if not patient_raw or not result_raw:
        raise ApiError(422, "multipart report requires patient and result fields.")

    data = await image_file.read(settings.max_upload_mb * 1024 * 1024 + 1)
    try:
        images.validate_image(data)
        images.check_allowed_size(data, settings.max_upload_mb)
    except ValueError as exc:
        raise ApiError(400, str(exc)) from exc

    try:
        patient = json.loads(patient_raw)
        result = json.loads(result_raw)
    except (ValueError, TypeError) as exc:
        raise ApiError(422, "patient and result must be JSON strings.") from exc

    return build_matlab_request(
        patient=patient,
        result=result,
        screeningId=str(screening_id) if screening_id else None,
        image_bytes=data,
    )


def build_matlab_request(
    *,
    patient: dict,
    result: dict,
    screeningId: str | None,
    image_bytes: bytes,
) -> dict:
    """Shape a request identical to what jeevana_report_json_api expects.

    imageBytes is sent as an integer array; MATLAB jsondecode gives a double
    vector and jeevana_report_api converts it with uint8(...).
    """
    return {
        "operation": "generate_report",
        "screeningId": screeningId or "JN-REPORT",
        "patient": {
            "name": patient.get("name", "Unknown"),
            "id": patient.get("id", "Unknown"),
            "gender": patient.get("gender", "Not specified"),
            "age": patient.get("age"),
        },
        "result": result,
        "imageBytes": list(image_bytes),
    }


def decode_base64(value: str) -> bytes:
    try:
        return base64.b64decode(value, validate=True)
    except (ValueError, TypeError) as exc:
        raise ApiError(400, "imageBase64 is not valid base64.") from exc


def _extract_pdf_bytes(matlab_out: dict) -> bytes:
    if "pdfBase64" in matlab_out:
        try:
            return base64.b64decode(matlab_out["pdfBase64"])
        except (ValueError, TypeError) as exc:
            raise ApiError(500, "Report service returned invalid PDF payload.") from exc
    if "pdfBytes" in matlab_out:
        try:
            return bytes(matlab_out["pdfBytes"])
        except TypeError as exc:
            raise ApiError(500, "Report service returned invalid PDF payload.") from exc
    raise ApiError(500, "Report service returned no PDF payload.")