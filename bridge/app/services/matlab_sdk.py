"""Production backend: MATLAB Compiler SDK generated Python package (SDK mode).

Compile `jeevana_netra_json_api.m` and `jeevana_report_json_api.m` with the
MATLAB Library Compiler as a PYTHON_PACKAGE. The generated package exposes the
two JSON-contract functions; this backend imports them and passes JSON
strings straight through, so no MATLAB type marshalling happens in Python.
"""

from __future__ import annotations

import importlib
import json
import logging

from ..errors import MatlabExecutionError
from .matlab_bridge import MatlabResult, MatlabService, decode_request_json

logger = logging.getLogger("jeevana.matlab.sdk")


class MatlabSdkService(MatlabService):
    def __init__(
        self,
        package_name: str,
        timeout_seconds: float = 600.0,
    ) -> None:
        super().__init__(timeout_seconds=timeout_seconds)
        self.package_name = package_name
        self._package = None
        self._functions = {}

    def _load(self) -> None:
        if self._package is not None:
            return
        try:
            mod = importlib.import_module(self.package_name)
            # MATLAB Compiler SDK packages expose an initialize() method or class
            self._package = mod.initialize() if hasattr(mod, "initialize") else mod
            self._functions = {
                "screen": getattr(self._package, "jeevana_netra_json_api", None)
                or getattr(mod, "jeevana_netra_json_api", None),
                "generate_report": getattr(self._package, "jeevana_report_json_api", None)
                or getattr(mod, "jeevana_report_json_api", None),
            }
        except Exception as exc:  # noqa: BLE001 - surfaced to health/503 only
            raise MatlabExecutionError(
                f"MATLAB SDK package '{self.package_name}' could not be imported: {exc}"
            ) from exc

    def is_configured(self) -> bool:
        try:
            self._load()
            return True
        except MatlabExecutionError:
            return False

    def _invoke(self, method: str, payload: dict) -> MatlabResult:
        self._load()
        fn = self._functions.get(method)
        if fn is None:
            raise MatlabExecutionError(f"MATLAB SDK has no method '{method}'.")

        request_json = json.dumps(payload)
        try:
            try:
                raw = fn(request_json, nargout=1)
            except TypeError:
                raw = fn(request_json)
            if hasattr(raw, "toarray") and callable(raw.toarray):
                raw = raw.toarray()
            text = str(raw)
        except MatlabExecutionError:
            raise
        except Exception as exc:  # noqa: BLE001
            logger.exception("MATLAB SDK call failed for %s", method)
            raise MatlabExecutionError("MATLAB screening service failed.") from exc

        result = decode_request_json(text)
        return MatlabResult(data=result)