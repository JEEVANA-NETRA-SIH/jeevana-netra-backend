"""POST /api/report validation tests.

Without a compiled MATLAB artifact the endpoint must 503 clearly. The model
PDF generation itself is tested in test_matlab_required.py when an artifact
is present.
"""

import base64

REPORT_URL = "/api/report"


def valid_report_payload(tiny_png: bytes) -> dict:
    return {
        "screeningId": "JN-2026-001",
        "patient": {"name": "Test Patient", "id": "P100", "gender": "F", "age": 45},
        "result": {
            "predictedClass": "NoDR",
            "confidence": 87.5,
            "confidenceStatus": "HIGH",
            "referralStatus": "NON-REFERABLE DR",
            "recommendation": "No referable DR detected.",
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
        "imageBase64": base64.b64encode(tiny_png).decode("ascii"),
    }


def test_report_missing_fields(client):
    response = client.post(REPORT_URL, json={"operation": "generate_report"})
    assert response.status_code == 422


def test_report_invalid_base64(client, tiny_png):
    payload = valid_report_payload(tiny_png)
    payload["imageBase64"] = "!!!!not base64!!!!"
    response = client.post(REPORT_URL, json=payload)
    assert response.status_code == 400
    assert "base64" in response.json()["detail"]


def test_report_invalid_json_body(client):
    response = client.post(
        REPORT_URL, content="{not json", headers={"Content-Type": "application/json"}
    )
    assert response.status_code == 422


def test_report_valid_but_matlab_not_configured(client, tiny_png):
    response = client.post(REPORT_URL, json=valid_report_payload(tiny_png))
    assert response.status_code == 503
    assert "not configured" in response.json()["detail"]


def test_report_multipart_invalid_image(client):
    response = client.post(
        REPORT_URL,
        data={
            "patient": '{"name":"T","id":"P1","gender":"F","age":30}',
            "result": '{"predictedClass":"NoDR"}',
        },
        files={"image": ("bad.txt", b"not an image", "text/plain")},
    )
    assert response.status_code == 400


def test_report_wrong_content_type(client):
    response = client.post(
        REPORT_URL, content="raw text", headers={"Content-Type": "text/plain"}
    )
    assert response.status_code == 415


def test_report_unsupported_format_ignored(client, tiny_png):
    """format=foo is tolerated but still routes to the (missing) MATLAB service."""
    response = client.post(REPORT_URL + "?format=pdf", json=valid_report_payload(tiny_png))
    assert response.status_code == 503


def test_report_json_image_not_an_image(client):
    payload = valid_report_payload(b"")
    payload["imageBase64"] = base64.b64encode(b"this is not an image").decode("ascii")
    response = client.post(REPORT_URL, json=payload)
    assert response.status_code == 400
    assert "not a PNG or JPEG" in response.json()["detail"]


def test_report_json_image_oversized(client, tiny_png, monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "max_upload_mb", 0)
    response = client.post(REPORT_URL, json=valid_report_payload(tiny_png))
    assert response.status_code == 400
    assert "exceeds" in response.json()["detail"]


def test_report_multipart_image_oversized(client, tiny_png, monkeypatch):
    from app.config import settings

    monkeypatch.setattr(settings, "max_upload_mb", 1)
    payload = b"\x89PNG\r\n\x1a\n" + b"\x00" * (2 * 1024 * 1024)
    response = client.post(
        REPORT_URL,
        data={
            "patient": '{"name":"T","id":"P1","gender":"F","age":30}',
            "result": '{"predictedClass":"NoDR"}',
        },
        files={"image": ("retina.png", payload, "image/png")},
    )
    assert response.status_code == 400
    assert "exceeds" in response.json()["detail"]


def test_report_filename_sanitized_from_matlab(client, tiny_png, monkeypatch):
    from app.api import report as report_module

    class Stub:
        def is_configured(self):
            return True

        def generate_report(self, request):
            pdf = b"%PDF-1.4 fake report"
            return {
                "status": "success",
                "filename": "evil\r\nX-Injected: 1.pdf",
                "pdfBase64": base64.b64encode(pdf).decode("ascii"),
            }

    monkeypatch.setattr(report_module, "get_matlab_service", lambda: Stub())

    response = client.post(REPORT_URL, json=valid_report_payload(tiny_png))
    assert response.status_code == 200
    disposition = response.headers["content-disposition"]
    assert "\r" not in disposition and "\n" not in disposition
    assert '"' not in disposition.replace('filename="', "", 1).rstrip('"')
    assert disposition == 'attachment; filename="evilX-Injected: 1.pdf"'


def test_report_returns_clean_json_filename(client, tiny_png, monkeypatch):
    from app.api import report as report_module

    class Stub:
        def is_configured(self):
            return True

        def generate_report(self, request):
            pdf = b"%PDF-1.4 fake report"
            return {
                "status": "success",
                "filename": 'ab"cd\r\n.pdf',
                "pdfBase64": base64.b64encode(pdf).decode("ascii"),
            }

    monkeypatch.setattr(report_module, "get_matlab_service", lambda: Stub())

    response = client.post(REPORT_URL + "?format=json", json=valid_report_payload(tiny_png))
    assert response.status_code == 200
    assert response.json()["filename"] == "abcd.pdf"


def test_report_invalid_pdf_payload(client, tiny_png, monkeypatch):
    from app.api import report as report_module

    class Stub:
        def is_configured(self):
            return True

        def generate_report(self, request):
            return {"status": "success", "pdfBase64": "!!!not base64!!!"}

    monkeypatch.setattr(report_module, "get_matlab_service", lambda: Stub())

    response = client.post(REPORT_URL, json=valid_report_payload(tiny_png))
    assert response.status_code == 500


def test_report_oversized_body_rejected(monkeypatch):
    import pytest
    from starlette.requests import Request

    from app.api.report import _reject_oversized_body
    from app.config import settings
    from app.errors import ApiError

    monkeypatch.setattr(settings, "max_upload_mb", 1)
    req = Request(
        {
            "type": "http",
            "method": "POST",
            "path": "/api/report",
            "headers": [(b"content-length", b"999999999")],
        }
    )
    with pytest.raises(ApiError) as exc_info:
        _reject_oversized_body(req)
    assert exc_info.value.status_code == 400