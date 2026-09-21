"""POST /api/screen tests.

In CI / local without the compiled MATLAB artifact (mode=none) the endpoint
must fail clearly with 503 — never with a fake prediction.
"""

from fastapi.testclient import TestClient

SCREEN_URL = "/api/screen"


def test_screen_without_image(client: TestClient):
    response = client.post(SCREEN_URL)
    assert response.status_code == 422


def test_screen_missing_file_field(client: TestClient, tiny_png):
    response = client.post(SCREEN_URL, files={"wrongname": ("x.png", tiny_png, "image/png")})
    assert response.status_code == 422


def test_screen_invalid_image_content(client: TestClient):
    payload = b"this is definitely not an image"
    response = client.post(
        SCREEN_URL,
        files={"image": ("fake.png", payload, "image/png")},
    )
    assert response.status_code == 400
    assert "not a PNG or JPEG" in response.json()["detail"]


def test_screen_oversized_upload(client: TestClient, monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "max_upload_mb", 1)
    response = client.post(
        SCREEN_URL,
        files={"image": ("big.png", b"\x89PNG\r\n\x1a\n" + b"\x00" * (2 * 1024 * 1024), "image/png")},
    )
    assert response.status_code == 400
    assert "exceeds" in response.json()["detail"]


def test_screen_valid_image_but_matlab_not_configured(client: TestClient, tiny_png):
    """A well-formed image must 503 when no MATLAB backend exists."""
    response = client.post(
        SCREEN_URL,
        files={"image": ("retina.png", tiny_png, "image/png")},
    )
    assert response.status_code == 503
    assert "not configured" in response.json()["detail"]


def test_screen_include_evidence_flag_accepted(client: TestClient, tiny_png, monkeypatch):
    """The includeEvidence query is parsed; still 503 without MATLAB."""
    from app.api import screen as screen_module

    captured = {}

    class Stub:
        def is_configured(self):
            return True

        def screen(self, image_bytes: bytes, include_evidence: bool) -> dict:
            captured["bytes"] = image_bytes
            captured["include_evidence"] = include_evidence
            return {"predictedClass": "NoDR"}

    monkeypatch.setattr(screen_module, "get_matlab_service", lambda: Stub())

    response = client.post(
        SCREEN_URL + "?includeEvidence=false",
        files={"image": ("retina.png", tiny_png, "image/png")},
    )
    assert response.status_code == 200
    assert captured["include_evidence"] is False
    assert captured["bytes"] == tiny_png