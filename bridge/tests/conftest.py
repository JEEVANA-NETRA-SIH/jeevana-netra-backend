"""Shared test fixtures.

The environment is pinned BEFORE importing the app so the bridge starts in a
deterministic state: no MATLAB artifact (mode=none), SQLite in a temp file,
production CORS origins present.
"""

from __future__ import annotations

import os
import tempfile

# Must run before app import.
os.environ["JEEVANA_NETRA_DB"] = os.path.join(
    tempfile.gettempdir(), f"jeevana_netra_test_{os.getpid()}.db"
)
os.environ["MATLAB_DEPLOY_MODE"] = "none"
os.environ["CORS_ORIGINS"] = (
    "https://jeevananetra.vercel.app,http://localhost:5173,http://127.0.0.1:5173"
)

import pytest  # noqa: E402
from fastapi.testclient import TestClient  # noqa: E402
from sqlalchemy import text  # noqa: E402

from app.database import get_engine  # noqa: E402
from app.main import app  # noqa: E402
from app.models import Base  # noqa: E402

engine = get_engine()


@pytest.fixture(autouse=True)
def clean_database():
    """Recreate tables and clear rows before every test."""
    Base.metadata.create_all(engine)
    yield
    with engine.begin() as conn:
        conn.execute(text("DELETE FROM screenings"))
        conn.execute(text("DELETE FROM patients"))


@pytest.fixture
def client():
    with TestClient(app) as test_client:
        yield test_client


TINY_PNG = bytes.fromhex(
    "89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
    "0000000d49444154789c626001000000ffff03000006000557bfabd400000000"
    "49454e44ae426082"
)


@pytest.fixture
def tiny_png() -> bytes:
    return TINY_PNG


@pytest.fixture
def make_screening_payload():
    def _make(patient_id: str = "P001") -> dict:
        return {
            "patient": {
                "patientId": patient_id,
                "name": "Test Patient",
                "age": 45,
                "gender": "F",
            },
            "screening": {
                "predictedClass": "NoDR",
                "confidence": 87.5,
                "confidenceStatus": "HIGH",
                "referralStatus": "NON-REFERABLE DR",
                "recommendation": "No referable DR detected by the AI screening model.",
                "qualityStatus": "Good",
                "qualityMessage": "Image quality is suitable for analysis.",
                "probabilities": {
                    "NoDR": 87.5,
                    "Mild": 5.0,
                    "Moderate": 3.5,
                    "Severe": 2.0,
                    "ProliferativeDR": 2.0,
                },
                "imageQuality": {"brightness": 110, "contrast": 45, "sharpness": 300},
                "lesionEvidence": [],
            },
        }

    return _make