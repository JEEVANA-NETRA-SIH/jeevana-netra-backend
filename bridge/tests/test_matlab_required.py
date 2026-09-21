"""Real-model integration tests.

These tests execute the ACTUAL compiled MATLAB pipeline (the genuine
ResNet-101 DR model). They are skipped unless a compiled MATLAB artifact and a
real retinal image are configured:

  JEEVANA_NETRA_TEST_IMAGE=/path/to/retinal-fundus-image.png
  MATLAB_DEPLOY_MODE=cli        JEEVANA_NETRA_EXE=/path/to/run_jeevana_service.sh
  # or
  MATLAB_DEPLOY_MODE=sdk        JEEVANA_NETRA_SDK_PACKAGE=jeevana_netra_sdk

This test never fakes a result: it fails loudly if MATLAB is unavailable.
"""

from __future__ import annotations

import base64
import os

import pytest

pytestmark = pytest.mark.matlab

_TEST_IMAGE = os.environ.get("JEEVANA_NETRA_TEST_IMAGE")


def _matlab_configured() -> bool:
    if not _TEST_IMAGE or not os.path.isfile(_TEST_IMAGE):
        return False
    mode = os.environ.get("MATLAB_DEPLOY_MODE", "cli")
    if mode == "cli":
        return bool(os.environ.get("JEEVANA_NETRA_EXE"))
    if mode == "sdk":
        return bool(os.environ.get("JEEVANA_NETRA_SDK_PACKAGE"))
    return False


def _activate_matlab(monkeypatch) -> None:
    from app.config import settings
    from app.services import factory

    mode = os.environ.get("MATLAB_DEPLOY_MODE", "cli")
    monkeypatch.setattr(settings, "matlab_mode", mode)
    if mode == "cli":
        monkeypatch.setattr(settings, "matlab_exe", os.environ["JEEVANA_NETRA_EXE"])
    elif mode == "sdk":
        monkeypatch.setattr(settings, "matlab_sdk_package", os.environ["JEEVANA_NETRA_SDK_PACKAGE"])
    factory._service = None


def _read_image() -> bytes:
    with open(_TEST_IMAGE, "rb") as handle:
        return handle.read()


@pytest.mark.skipif(
    not _matlab_configured(),
    reason="Compiled MATLAB artifact + test image not configured.",
)
def test_real_matlab_screening(client, monkeypatch):
    _activate_matlab(monkeypatch)
    response = client.post(
        "/api/screen",
        files={
            "image": (
                os.path.basename(_TEST_IMAGE),
                _read_image(),
                "application/octet-stream",
            )
        },
    )
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["predictedClass"] in {
        "NoDR",
        "Mild",
        "Moderate",
        "Severe",
        "ProliferativeDR",
    }
    assert 0.0 <= body["confidence"] <= 100.0
    assert body["qualityStatus"] in ("Good", "Poor")
    assert "probabilities" in body
    assert "lesionEvidence" in body


@pytest.mark.skipif(
    not _matlab_configured(),
    reason="Compiled MATLAB artifact + test image not configured.",
)
def test_real_matlab_report(client, monkeypatch):
    _activate_matlab(monkeypatch)
    payload = {
        "screeningId": "JN-2026-001",
        "patient": {"name": "Integration", "id": "INT1", "gender": "F", "age": 50},
        "result": {
            "predictedClass": "NoDR",
            "confidence": 90.0,
            "confidenceStatus": "HIGH",
            "referralStatus": "NON-REFERABLE DR",
            "recommendation": "No referable DR detected by the AI screening model.",
            "qualityStatus": "Good",
            "qualityMessage": "Image quality is suitable for analysis.",
        },
        "imageBase64": base64.b64encode(_read_image()).decode("ascii"),
    }
    response = client.post("/api/report", json=payload)
    assert response.status_code == 200, response.text
    assert response.headers["content-type"] == "application/pdf"
    assert len(response.content) > 1000
    assert response.content[:4] == b"%PDF"