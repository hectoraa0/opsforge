"""PostgreSQL-backed integration smoke test, used by CI and local users."""

import json
import time
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

BASE = "http://127.0.0.1:8000"


def request(path: str, method: str = "GET", payload: dict | None = None) -> tuple[int, dict]:
    headers = {"Content-Type": "application/json"}
    data = json.dumps(payload).encode() if payload is not None else None
    req = Request(BASE + path, data=data, method=method, headers=headers)
    with urlopen(req, timeout=5) as response:
        return response.status, json.load(response)


def wait_ready(timeout_seconds: int = 150) -> None:
    deadline = time.monotonic() + timeout_seconds
    while time.monotonic() < deadline:
        try:
            status, body = request("/health/ready")
            if status == 200 and body == {"status": "ready"}:
                return
        except (OSError, URLError, HTTPError, ValueError):
            pass
        time.sleep(3)
    raise TimeoutError("API did not become ready; inspect `docker compose logs api`")


def main() -> None:
    wait_ready()
    status, created = request(
        "/api/v1/incidents", "POST", {"title": "Smoke test incident", "severity": "low"}
    )
    assert status == 201 and created["status"] == "open"
    incident_id = created["id"]
    status, updated = request(
        f"/api/v1/incidents/{incident_id}/status", "PATCH", {"status": "resolved"}
    )
    assert status == 200 and updated["status"] == "resolved"
    status, fetched = request(f"/api/v1/incidents/{incident_id}")
    assert status == 200 and fetched["status"] == "resolved"
    print("PASS: readiness, PostgreSQL create/read/update, and HTTP API")


if __name__ == "__main__":
    main()
