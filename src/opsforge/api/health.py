import logging

from fastapi import APIRouter, HTTPException, status
from sqlalchemy import text
from sqlalchemy.exc import SQLAlchemyError

from opsforge.db.session import engine

router = APIRouter(tags=["health"])
log = logging.getLogger(__name__)


@router.get("/health/live")
def live() -> dict[str, str]:
    """Process is running. Never depend on the database for liveness."""
    return {"status": "alive"}


@router.get("/health/ready")
def ready() -> dict[str, str]:
    """Ready to serve requests only when the database is reachable."""
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
    except SQLAlchemyError as exc:
        log.warning("database_readiness_failed: %s", type(exc).__name__)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE, detail="database not ready"
        ) from exc
    return {"status": "ready"}
