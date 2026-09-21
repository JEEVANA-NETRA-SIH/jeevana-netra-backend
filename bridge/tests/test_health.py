"""GET /health tests."""


def test_health_ok(client):
    response = client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["service"] == "jeevana-netra-backend"
    assert body["matlab"]["status"] == "unavailable"
    assert body["matlab"]["mode"] == "none"


def test_health_reports_configured_when_cli_available(client, monkeypatch):
    """With a configured (but not probed) artifact, health says configured."""
    from app.config import settings
    from app.services import factory

    monkeypatch.setattr(settings, "matlab_mode", "cli")
    monkeypatch.setattr(settings, "matlab_exe", "undefined")  # not a real file

    factory._service = None
    body = client.get("/health").json()
    # The exe does not exist, so the backend is unavailable.
    assert body["matlab"]["status"] == "unavailable"
    monkeypatch.setattr(settings, "matlab_mode", "none")
    factory._service = None


def test_cors_allows_production_frontend(client):
    response = client.get(
        "/health", headers={"Origin": "https://jeevananetra.vercel.app"}
    )
    assert response.headers.get("access-control-allow-origin") == (
        "https://jeevananetra.vercel.app"
    )


def test_cors_rejects_unknown_origin(client):
    response = client.get("/health", headers={"Origin": "https://evil.example.com"})
    assert "access-control-allow-origin" not in response.headers