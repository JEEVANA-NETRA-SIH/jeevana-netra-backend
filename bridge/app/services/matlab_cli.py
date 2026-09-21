"""Production backend: MATLAB Compiler standalone executable (CLI mode).

The MATLAB side compiles `run_jeevana_service.m` with `mcc -m` into a
standalone executable plus a `run_jeevana_service.sh` launcher. The bridge
spawns:

    run_jeevana_service.sh <request.json> <response.json>

and reads the JSON result written by MATLAB. Full stdout/stderr output is kept
for logging; only the JSON contract crosses the service boundary.
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import tempfile
import threading
from pathlib import Path

from ..errors import MatlabExecutionError
from .matlab_bridge import MatlabResult, MatlabService, decode_request_json

logger = logging.getLogger("jeevana.matlab.cli")


class MatlabCliService(MatlabService):
    def __init__(
        self,
        executable: str,
        timeout_seconds: float = 600.0,
        tmp_dir: str | None = None,
        prefdir: str | None = None,
    ) -> None:
        super().__init__(timeout_seconds=timeout_seconds, tmp_dir=tmp_dir)
        self.executable = Path(executable)
        self.prefdir = prefdir
        self._lock = threading.Lock()

    def is_configured(self) -> bool:
        if not self.executable.exists():
            logger.error("MATLAB executable not found: %s", self.executable)
            return False
        return True

    # ------------------------------------------------------------------
    def _invoke(self, method: str, payload: dict) -> MatlabResult:
        if not self.is_configured():
            raise MatlabExecutionError(
                "MATLAB executable is not available; check JEEVANA_NETRA_EXE."
            )

        workdir = Path(self.tmp_dir or tempfile.gettempdir())
        workdir.mkdir(parents=True, exist_ok=True)

        # Unique files -> concurrent requests never collide.
        request_file = workdir / f"jeevana_req_{os.getpid()}_{next_token()}.json"
        response_file = workdir / f"jeevana_resp_{os.getpid()}_{next_token()}.json"

        try:
            request_file.write_text(json.dumps(payload), encoding="utf-8")

            env = os.environ.copy()
            env["JEEVANA_SERVICE_METHOD"] = method
            if self.prefdir:
                Path(self.prefdir).mkdir(parents=True, exist_ok=True)
                env["MATLAB_PREFDIR"] = self.prefdir
                env.setdefault("HOME", self.prefdir)

            proc = subprocess.run(
                [str(self.executable), str(request_file), str(response_file)],
                capture_output=True,
                text=True,
                timeout=self.timeout_seconds,
                env=env,
                cwd=str(workdir),
            )

            console = (proc.stdout or "") + (proc.stderr or "")
            if proc.returncode != 0:
                logger.error("MATLAB exit=%s stderr=%s", proc.returncode, proc.stderr[-2000:])
                raise MatlabExecutionError(
                    "MATLAB screening service failed (see server logs)."
                )

            if not response_file.exists():
                logger.error("MATLAB produced no response file. output=%s", console[-2000:])
                raise MatlabExecutionError(
                    "MATLAB screening service produced no result (see server logs)."
                )

            try:
                raw = response_file.read_text(encoding="utf-8")
            except OSError as exc:
                logger.error("MATLAB response file unreadable: %s", exc)
                raise MatlabExecutionError(
                    "MATLAB screening service produced an unreadable result."
                ) from exc
            result = decode_request_json(raw)
            return MatlabResult(data=result, output=console)

        except subprocess.TimeoutExpired:
            logger.error("MATLAB request timed out after %ss (%s)", self.timeout_seconds, method)
            raise MatlabExecutionError(
                "MATLAB screening service timed out (see server logs)."
            ) from None
        finally:
            for f in (request_file, response_file):
                try:
                    f.unlink(missing_ok=True)
                except OSError:
                    pass


_counter = 0
_counter_lock = threading.Lock()


def next_token() -> str:
    global _counter
    with _counter_lock:
        _counter += 1
        return str(_counter)