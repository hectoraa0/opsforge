from datetime import datetime
from enum import StrEnum

from pydantic import BaseModel, ConfigDict, Field, field_validator


class Severity(StrEnum):
    low = "low"
    medium = "medium"
    high = "high"
    critical = "critical"


class IncidentStatus(StrEnum):
    open = "open"
    acknowledged = "acknowledged"
    resolved = "resolved"


class IncidentCreate(BaseModel):
    title: str = Field(min_length=3, max_length=120)
    description: str = Field(default="", max_length=4000)
    severity: Severity

    @field_validator("title")
    @classmethod
    def not_blank(cls, title: str) -> str:
        cleaned = title.strip()
        if not cleaned:
            raise ValueError("title must not be blank")
        return cleaned


class IncidentStatusUpdate(BaseModel):
    status: IncidentStatus


class IncidentRead(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    description: str
    severity: Severity
    status: IncidentStatus
    created_at: datetime
    updated_at: datetime
