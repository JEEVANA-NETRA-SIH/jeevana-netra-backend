"""Select the active MATLAB backend from configuration.

MATLAB_DEPLOY_MODE:
  - "cli": MATLAB Compiler standalone executable (JEEVANA_NETRA_EXE)
  - "sdk": MATLAB Compiler SDK Python package (JEEVANA_NETRA_SDK_PACKAGE)
  - anything else / unset: no compiled artifact, services return 503
"""

from __future__ import annotations

import logging

from ..config import settings
from .matlab_bridge import MatlabService
from .matlab_cli import MatlabCliService
from .matlab_sdk import MatlabSdkService

logger = logging.getLogger("jeevana.matlab.factory")

_service: MatlabService | None = None


def get_matlab_service() -> MatlabService | None:
    """Return the configured MatlabService, or None when MATLAB is absent."""
    global _service
    if _service is not None:
        return _service

    mode = settings.matlab_mode or "none"
    if mode == "cli":
        if not settings.matlab_exe:
            logger.error("MATLAB_DEPLOY_MODE=cli but JEEVANA_NETRA_EXE is not set.")
            return None
        _service = MatlabCliService(
            executable=settings.matlab_exe or "",
            timeout_seconds=settings.matlab_timeout_seconds,
            tmp_dir=settings.tmp_dir,
            prefdir=settings.matlab_prefdir,
        )
    elif mode == "sdk":
        if not settings.matlab_sdk_package:
            logger.error("MATLAB_DEPLOY_MODE=sdk but JEEVANA_NETRA_SDK_PACKAGE is not set.")
            return None
        _service = MatlabSdkService(
            package_name=settings.matlab_sdk_package or "",
            timeout_seconds=settings.matlab_timeout_seconds,
        )
    else:
        _service = None

    if _service is not None and not _service.is_configured():
        logger.error("Configured MATLAB backend is not available (mode=%s).", mode)
        _service = None

    return _service


def matlab_health_status() -> dict:
    """Honest health status: never claims 'initialized' without a real run."""
    service = get_matlab_service()
    if service is not None:
        return {
            "status": MatlabService.runtime_status(),
            "mode": settings.matlab_mode,
        }
    mode = settings.matlab_mode or "none"
    detail = (
        "MATLAB backend selected but not available."
        if mode not in ("", "none")
        else "MATLAB screening service is not configured."
    )
    return {
        "status": "unavailable",
        "mode": mode,
        "detail": detail,
    }
