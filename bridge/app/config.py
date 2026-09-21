"""Application configuration.

All values are read from environment variables so the same code runs in
local development, inside Docker, and on Render. Never put secrets in this
file.
"""

from __future__ import annotations

import os
from dataclasses import dataclass, field
from pathlib import Path

# Default allowed browser origins. The deployed Vercel frontend is always
# allowed; localhost entries are kept for development only.
DEFAULT_CORS_ORIGINS = [
    "https://jeevananetra.vercel.app",
    "http://localhost:5173",
    "http://127.0.0.1:5173",
    "http://localhost:4173",
    "http://127.0.0.1:4173",
]


def _env_bool(name: str, default: bool = False) -> bool:
    raw = os.getenv(name, "").strip().lower()
    if raw in ("1", "true", "yes", "on"):
        return True
    if raw in ("0", "false", "no", "off"):
        return False
    return default


@dataclass
class Settings:
    service_name: str = "jeevana-netra-backend"
    port: int = 8000

    # --- Database ---------------------------------------------------------
    # Prefer DATABASE_URL for Postgres later. JEEVANA_NETRA_DB is the
    # SQLite file path kept for compatibility with the MATLAB patient API.
    database_url: str | None = None
    jeevana_netra_db: str | None = None

    # --- MATLAB deployment mode -------------------------------------------
    # none -> no compiled MATLAB artifact available (dev fallback, 503)
    # cli  -> spawn a MATLAB Compiler standalone executable
    # sdk  -> call a MATLAB Compiler SDK generated Python package
    matlab_mode: str = "none"
    matlab_exe: str | None = None
    matlab_sdk_package: str | None = None
    matlab_timeout_seconds: float = 600.0

    # --- HTTP / CORS ------------------------------------------------------
    cors_origins: list[str] = field(default_factory=lambda: list(DEFAULT_CORS_ORIGINS))
    api_key: str | None = None
    max_upload_mb: int = 20

    # --- MATLAB Runtime on Linux ------------------------------------------
    matlab_prefdir: str | None = None
    tmp_dir: str | None = None

    @classmethod
    def from_env(cls) -> "Settings":
        settings = cls()

        if raw_port := os.getenv("PORT"):
            settings.port = int(raw_port)

        settings.database_url = os.getenv("DATABASE_URL") or None
        settings.jeevana_netra_db = os.getenv("JEEVANA_NETRA_DB") or None

        settings.matlab_mode = os.getenv("MATLAB_DEPLOY_MODE", "none").strip().lower()
        settings.matlab_exe = os.getenv("JEEVANA_NETRA_EXE") or None
        settings.matlab_sdk_package = os.getenv("JEEVANA_NETRA_SDK_PACKAGE") or None
        if raw_timeout := os.getenv("MATLAB_TIMEOUT_SECONDS"):
            settings.matlab_timeout_seconds = float(raw_timeout)

        if raw_origins := os.getenv("CORS_ORIGINS"):
            settings.cors_origins = [
                origin.strip() for origin in raw_origins.split(",") if origin.strip()
            ]

        settings.api_key = os.getenv("JEEVANA_API_KEY") or None
        if raw_max := os.getenv("MAX_UPLOAD_MB"):
            settings.max_upload_mb = int(raw_max)

        settings.matlab_prefdir = os.getenv("MATLAB_PREFDIR") or None
        settings.tmp_dir = os.getenv("TMP_DIR") or None

        return settings

    @property
    def default_db_dir(self) -> Path:
        base = Path(__file__).resolve().parent.parent
        return base / "data"

    @property
    def resolved_database_url(self) -> str:
        """Resolve the SQLAlchemy database URL.

        Priority: DATABASE_URL > JEEVANA_NETRA_DB (SQLite file) > default
        SQLite file inside bridge/data/.
        """
        if self.database_url:
            return self.database_url

        if self.jeevana_netra_db:
            db_path = Path(self.jeevana_netra_db)
            db_path.parent.mkdir(parents=True, exist_ok=True)
            return f"sqlite:///{db_path}"

        data_dir = self.default_db_dir
        data_dir.mkdir(parents=True, exist_ok=True)
        return f"sqlite:///{data_dir / 'jeevana_netra.db'}"


settings = Settings.from_env()