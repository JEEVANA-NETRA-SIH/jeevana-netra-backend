"""Database engine, session factory and startup initialization.

SQLite is the default (file configured via JEEVANA_NETRA_DB). For Render
production the same code works with PostgreSQL by setting DATABASE_URL —
no repository layer changes are required because all persistence goes
through SQLAlchemy.
"""

from __future__ import annotations

from collections.abc import Iterator

from sqlalchemy import create_engine, event
from sqlalchemy.orm import Session, sessionmaker

from .config import settings
from .models import Base

_engine = None


def _build_engine(url: str):
    if url.startswith("sqlite"):
        url = url.replace("sqlite:///", "")
        from pathlib import Path

        # Relative sqlite paths are resolved against the bridge directory.
        if not Path(url).is_absolute():
            from .config import settings as s

            url = str(s.default_db_dir.parent / url)
        engine = create_engine(
            f"sqlite:///{url}",
            connect_args={"check_same_thread": False},
        )

        @event.listens_for(engine, "connect")
        def _set_sqlite_pragma(dbapi_connection, connection_record):  # noqa: ARG001
            cursor = dbapi_connection.cursor()
            cursor.execute("PRAGMA foreign_keys = ON")
            cursor.close()

        return engine

    return create_engine(url)


def _session_factory():
    return sessionmaker(
        bind=get_engine(), autoflush=False, autocommit=False, expire_on_commit=False
    )


def get_engine():
    global _engine
    if _engine is None:
        _engine = _build_engine(settings.resolved_database_url)
    return _engine


def reset_engine() -> None:
    """Close and drop the cached engine (used by tests)."""
    global _engine
    if _engine is not None:
        _engine.dispose()
        _engine = None


def init_db() -> None:
    Base.metadata.create_all(bind=get_engine())


SessionLocal = _session_factory()


def get_db() -> Iterator[Session]:
    """FastAPI dependency yielding a request-scoped session."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()