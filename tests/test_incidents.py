def test_incident_lifecycle(client):
    created = client.post(
        "/api/v1/incidents",
        json={"title": " API is down ", "description": "Synthetic test", "severity": "high"},
    )
    assert created.status_code == 201
    assert created.json()["id"] == 1
    assert created.json()["title"] == "API is down"
    assert created.json()["status"] == "open"

    fetched = client.get("/api/v1/incidents/1")
    assert fetched.status_code == 200
    assert fetched.json()["severity"] == "high"

    changed = client.patch("/api/v1/incidents/1/status", json={"status": "resolved"})
    assert changed.status_code == 200
    assert changed.json()["status"] == "resolved"

    listed = client.get("/api/v1/incidents")
    assert listed.status_code == 200
    assert len(listed.json()) == 1
    assert listed.json()[0]["status"] == "resolved"


def test_invalid_inputs(client):
    blank = client.post("/api/v1/incidents", json={"title": "   ", "severity": "high"})
    assert blank.status_code == 422

    wrong_severity = client.post(
        "/api/v1/incidents", json={"title": "Something broke", "severity": "nuclear"}
    )
    assert wrong_severity.status_code == 422

    missing = client.get("/api/v1/incidents/123456")
    assert missing.status_code == 404

    invalid_status = client.patch("/api/v1/incidents/1/status", json={"status": "deleted"})
    assert invalid_status.status_code == 422

    too_large_page = client.get("/api/v1/incidents?limit=5000")
    assert too_large_page.status_code == 422


def test_pagination_order(client):
    for title in ("First incident", "Second incident", "Third incident"):
        result = client.post(
            "/api/v1/incidents", json={"title": title, "severity": "low"}
        )
        assert result.status_code == 201
    result = client.get("/api/v1/incidents?offset=1&limit=1")
    assert result.status_code == 200
    assert [record["title"] for record in result.json()] == ["Second incident"]
