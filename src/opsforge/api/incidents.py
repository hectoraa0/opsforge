from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy import select
from sqlalchemy.orm import Session

from opsforge.db.models import Incident
from opsforge.db.session import get_session
from opsforge.schemas import IncidentCreate, IncidentRead, IncidentStatusUpdate

router = APIRouter(prefix="/api/v1/incidents", tags=["incidents"])
SessionDep = Annotated[Session, Depends(get_session)]


@router.get("", response_model=list[IncidentRead])
def list_incidents(
    session: SessionDep,
    offset: Annotated[int, Query(ge=0)] = 0,
    limit: Annotated[int, Query(ge=1, le=100)] = 50,
) -> list[Incident]:
    statement = select(Incident).order_by(Incident.id.desc()).offset(offset).limit(limit)
    return list(session.scalars(statement).all())


@router.post("", response_model=IncidentRead, status_code=status.HTTP_201_CREATED)
def create_incident(payload: IncidentCreate, session: SessionDep) -> Incident:
    incident = Incident(
        title=payload.title,
        description=payload.description,
        severity=payload.severity.value,
        status="open",
    )
    session.add(incident)
    session.commit()
    session.refresh(incident)
    return incident


@router.get("/{incident_id}", response_model=IncidentRead)
def get_incident(incident_id: int, session: SessionDep) -> Incident:
    incident = session.get(Incident, incident_id)
    if incident is None:
        raise HTTPException(status_code=404, detail="incident not found")
    return incident


@router.patch("/{incident_id}/status", response_model=IncidentRead)
def set_status(incident_id: int, payload: IncidentStatusUpdate, session: SessionDep) -> Incident:
    incident = session.get(Incident, incident_id)
    if incident is None:
        raise HTTPException(status_code=404, detail="incident not found")
    incident.status = payload.status.value
    session.commit()
    session.refresh(incident)
    return incident
