"""Pydantic request/response schemas.

Field names deliberately mirror the MATLAB result structure where possible
(probabilities: NoDR/Mild/Moderate/Severe/ProliferativeDR, imageQuality:
brightness/contrast/sharpness). Extra result fields are preserved so the
full screening payload is never silently dropped.
"""

from __future__ import annotations

from typing import Any

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator

# ---------------------------------------------------------------------------
# Patients
# ---------------------------------------------------------------------------


class PatientIn(BaseModel):
    model_config = ConfigDict(extra="allow", populate_by_name=True)

    patientId: str | None = Field(default=None, max_length=64)
    id: str | None = Field(default=None, max_length=64)
    name: str = Field(..., min_length=1, max_length=200)
    age: float | None = Field(default=None, ge=0, le=130)
    gender: str | None = Field(default=None, max_length=32)

    @model_validator(mode="after")
    def _sync_ids(self) -> "PatientIn":
        resolved = (self.patientId or self.id or "").strip()
        if not resolved:
            raise ValueError("patientId must not be blank.")
        self.patientId = resolved
        if self.id is None:
            self.id = resolved
        return self


class PatientRecord(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    name: str
    age: float | None = None
    gender: str | None = None
    lastScreening: str | None = None
    result: str | None = None
    risk: str | None = None
    status: str | None = None


# ---------------------------------------------------------------------------
# Screening results
# ---------------------------------------------------------------------------


class ProbabilityMap(BaseModel):
    model_config = ConfigDict(extra="allow")

    NoDR: float = 0.0
    Mild: float = 0.0
    Moderate: float = 0.0
    Severe: float = 0.0
    ProliferativeDR: float = 0.0


class ImageQuality(BaseModel):
    model_config = ConfigDict(extra="allow")

    brightness: float | None = None
    contrast: float | None = None
    sharpness: float | None = None


class ScreeningResultIn(BaseModel):
    """A screening result produced by the real MATLAB model.

    extra="allow" preserves any additional fields MATLAB returns so nothing
    is lost while still validating the core contract.
    """

    model_config = ConfigDict(extra="allow")

    predictedClass: str
    confidence: float = 0.0
    confidenceStatus: str | None = None
    referralStatus: str | None = None
    recommendation: str | None = None
    qualityStatus: str | None = None
    qualityMessage: str | None = None
    probabilities: dict[str, Any] = Field(default_factory=dict)
    imageQuality: dict[str, Any] = Field(default_factory=dict)
    lesionEvidence: list[dict[str, Any]] | Any = Field(default_factory=list)


class ScreeningSaveIn(BaseModel):
    """Payload for POST /api/screenings (persist a real model result)."""

    patient: PatientIn
    screening: ScreeningResultIn
    screeningDate: str | None = None


# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------


class ReportPatientIn(BaseModel):
    model_config = ConfigDict(extra="allow", populate_by_name=True)

    name: str = Field(default="Unknown", min_length=1, max_length=200)
    id: str | None = Field(default=None, max_length=64)
    patientId: str | None = Field(default=None, max_length=64)
    gender: str | None = Field(default=None, max_length=32)
    age: float | None = Field(default=None)

    @model_validator(mode="after")
    def _sync_ids(self) -> "ReportPatientIn":
        resolved = (self.id or self.patientId or "Unknown").strip()
        self.id = resolved
        if self.patientId is None:
            self.patientId = resolved
        return self


class ReportRequestIn(BaseModel):
    model_config = ConfigDict(extra="allow")

    operation: str = "generate_report"
    screeningId: str | None = None
    patient: ReportPatientIn
    result: dict[str, Any] | ScreeningResultIn = Field(default_factory=dict)
    screening: dict[str, Any] | ScreeningResultIn | None = None
    imageBase64: str = Field(..., min_length=1)

    @model_validator(mode="after")
    def _resolve_result(self) -> "ReportRequestIn":
        if not self.result and self.screening:
            self.result = self.screening
        return self


# ---------------------------------------------------------------------------
# Common responses
# ---------------------------------------------------------------------------


class HealthResponse(BaseModel):
    status: str
    service: str
    matlab: dict[str, Any]