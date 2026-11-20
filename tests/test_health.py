def test_live(client):
    response = client.get("/health/live")
    assert response.status_code == 200
    assert response.json() == {"status": "alive"}
    assert response.headers.get("X-Request-ID")


def test_metrics(client):
    client.get("/health/live")
    response = client.get("/metrics")
    assert response.status_code == 200
    assert "opsforge_http_requests_total" in response.text
    assert "opsforge_http_request_duration_seconds" in response.text
