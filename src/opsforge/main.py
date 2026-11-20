import logging
from time import perf_counter
from uuid import uuid4

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest

from opsforge.api import health, incidents
from opsforge.config import settings
from opsforge.logging_config import configure_logging

configure_logging(settings.log_level)
log = logging.getLogger("opsforge.http")

HTTP_REQUESTS = Counter(
    "opsforge_http_requests_total",
    "Total HTTP requests handled by the application",
    ["method", "route", "status_code"],
)
HTTP_DURATION = Histogram(
    "opsforge_http_request_duration_seconds",
    "Duration of HTTP requests",
    ["method", "route"],
    buckets=(0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5),
)

app = FastAPI(title=settings.app_name, version="0.1.0")
app.include_router(health.router)
app.include_router(incidents.router)


@app.middleware("http")
async def observe_requests(request: Request, call_next):
    start = perf_counter()
    request_id = str(uuid4())
    status_code = 500
    try:
        response: Response = await call_next(request)
        status_code = response.status_code
        response.headers["X-Request-ID"] = request_id
        return response
    finally:
        duration = perf_counter() - start
        # The templated route prevents unbounded metric labels for /incidents/123 etc.
        matched_route = request.scope.get("route")
        route = getattr(matched_route, "path", "unmatched")
        if request.url.path != "/metrics":
            HTTP_REQUESTS.labels(request.method, route, str(status_code)).inc()
            HTTP_DURATION.labels(request.method, route).observe(duration)
        log.info(
            "http_request",
            extra={
                "request_id": request_id,
                "method": request.method,
                "path": request.url.path,
                "status_code": status_code,
                "duration_ms": round(duration * 1000, 2),
            },
        )


@app.get("/metrics", include_in_schema=False)
def metrics() -> Response:
    """Prometheus text exposition. Keep private when deploying outside localhost."""
    return Response(content=generate_latest(), media_type=CONTENT_TYPE_LATEST)
