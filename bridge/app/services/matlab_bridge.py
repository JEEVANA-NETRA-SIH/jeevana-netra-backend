"""MatlabScreeningService adapter.

Defines the interface between the HTTP bridge and the compiled MATLAB
pipelines. Two production backends exist: the compiled standalone executable
(matlab_cli) and the MATLAB Compiler SDK Python package (matlab_sdk).

A "none" mode is the development fallback: the service reports itself as
unconfigured and the API answers with HTTP 503 instead of inventing results.
"""

from __future__ import annotations

import base64
import json
import threading
from abc import ABC, abstractmethod
from dataclasses import dataclass

from ..errors import MatlabExecutionError

# Tracks whether any real MATLAB call has succeeded in this process. Used by
# /health so we never claim the model is operational unless it has actually
# loaded and produced a result.
_runtime_initialized = False
_runtime_lock = threading.Lock()


@dataclass
class MatlabResult:
    """Validated payload returned from the deployed MATLAB pipeline."""

    data: dict
    output: str = ""

    @property
    def ok(self) -> bool:
        return bool(self.data) and self.data.get("status", "error") == "success"


@dataclass
class MatlabService(ABC):
    timeout_seconds: float = 600.0
    tmp_dir: str | None = None

    @abstractmethod
    def is_configured(self) -> bool:
        """True when the compiled MATLAB artifact is present and usable."""

    @abstractmethod
    def _invoke(self, method: str, payload: dict) -> MatlabResult:
        """Run `method` (screen | generate_report) with `payload`."""

    @classmethod
    def mark_initialized(cls) -> None:
        global _runtime_initialized
        with _runtime_lock:
            _runtime_initialized = True

    @classmethod
    def runtime_status(cls) -> str:
        with _runtime_lock:
            if _runtime_initialized:
                return "initialized"
        return "configured"

    # ------------------------------------------------------------------
    # Public API
    # ------------------------------------------------------------------

    def screen(self, image_bytes: bytes, include_evidence: bool = True) -> dict:
        payload = {
            "operation": "screen",
            "imageBase64": base64.b64encode(image_bytes).decode("ascii"),
            "includeEvidence": bool(include_evidence),
        }
        result = self._invoke("screen", payload)
        if not result.ok:
            raise MatlabExecutionError(self._error_message(result))
        screening = (result.data.get("screening") or {}).copy()
        if not screening:
            raise MatlabExecutionError("MATLAB returned a screening with no result data.")
        self.mark_initialized()
        return screening

    def generate_report(self, request: dict) -> dict:
        payload = dict(request)
        payload["operation"] = "generate_report"
        result = self._invoke("generate_report", payload)
        if not result.ok:
            raise MatlabExecutionError(self._error_message(result))
        out = result.data.copy()
        self.mark_initialized()
        return out

    def _error_message(self, result: MatlabResult) -> str:
        raw = result.data.get("message") or result.output or "MATLAB service error."
        return str(raw)


def decode_request_json(raw: str) -> dict:
    try:
        payload = json.loads(raw)
    except (ValueError, TypeError) as exc:
        raise MatlabExecutionError(
            "MATLAB returned an invalid JSON response."
        ) from exc
    if not isinstance(payload, dict):
        raise MatlabExecutionError("MATLAB returned a non-object response.")
    return payload