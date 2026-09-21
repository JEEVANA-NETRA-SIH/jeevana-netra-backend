"""GET /api/patients and GET /api/patients/{id}."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Path, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..errors import NotFoundError
from ..security import require_api_key
from .. import repositories

router = APIRouter(dependencies=[Depends(require_api_key)])


@router.get("/api/patients", tags=["patients"])
def list_patients(
    limit: int = Query(default=200, ge=1, le=1000),
    db: Session = Depends(get_db),
) -> dict:
    rows = repositories.list_patients(db, limit=limit)
    return {
        "status": "success",
        "operation": "get_patient_records",
        "count": len(rows),
        "patientRecords": rows,
    }


@router.get("/api/patients/{patient_id}", tags=["patients"])
def patient_history(
    patient_id: str = Path(..., min_length=1, max_length=64),
    db: Session = Depends(get_db),
) -> dict:
    patient, history = repositories.get_patient_history(db, patient_id.strip())
    if patient is None:
        raise NotFoundError(f"Patient {patient_id} not found.")
    return {
        "status": "success",
        "operation": "get_patient_history",
        "patientId": patient.patient_id,
        "count": len(history),
        "history": history,
    }