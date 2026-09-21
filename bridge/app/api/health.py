"""GET /health — liveness and MATLAB availability probe."""

from __future__ import annotations

from fastapi import APIRouter

from ..schemas import HealthResponse
from ..services.factory import matlab_health_status

router = APIRouter()


@router.get("/health", response_model=HealthResponse, tags=["health"])
def health() -> HealthResponse:
    return HealthResponse(
        status="ok",
        service="jeevana-netra-backend",
        matlab=matlab_health_status(),
    )