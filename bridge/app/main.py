"""Jeevana Netra HTTP bridge application.

Wires CORS, database initialization, global error handling and the API
routers. The bridge never fabricates AI results: every screening/report
response comes from the compiled MATLAB pipeline or an explicit error.
"""

from __future__ import annotations

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from .api import health, patients, report, screen, screenings
from .config import settings
from .database import init_db
from .errors import ApiError

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s %(message)s",
)
logger = logging.getLogger("jeevana")


@asynccontextmanager
async def lifespan(app: FastAPI):
    logger.info("Initializing Jeevana Netra database.")
    init_db()
    mode = settings.matlab_mode
    logger.info(
        "MATLAB deployment mode=%s (cli=%s, sdk=%s)",
        mode,
        settings.matlab_exe,
        settings.matlab_sdk_package,
    )
    yield


app = FastAPI(
    title="Jeevana Netra Backend",
    description=(
        "HTTP bridge around the compiled MATLAB diabetic retinopathy "
        "screening, explainability and report pipeline. AI-assisted "
        "prototype: not a substitute for professional medical diagnosis."
    ),
    version="1.0.0",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


@app.exception_handler(ApiError)
async def api_error_handler(request: Request, exc: ApiError) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


@app.exception_handler(404)
async def not_found_handler(request: Request, exc: Exception) -> JSONResponse:
    return JSONResponse(status_code=404, content={"detail": "Not found."})


@app.exception_handler(500)
async def internal_handler(request: Request, exc: Exception) -> JSONResponse:
    logger.exception("Unhandled error on %s %s", request.method, request.url.path)
    return JSONResponse(status_code=500, content={"detail": "Internal server error."})


app.include_router(health.router)
app.include_router(screen.router)
app.include_router(screenings.router)
app.include_router(patients.router)
app.include_router(report.router)