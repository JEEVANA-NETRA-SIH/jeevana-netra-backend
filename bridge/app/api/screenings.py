"""POST/GET /api/screenings — persistence of real screening results and history."""

from __future__ import annotations

from fastapi import APIRouter, Depends, Query
from sqlalchemy.orm import Session

from ..database import get_db
from ..schemas import ScreeningSaveIn
from ..screening_logic import risk_level_for, screening_status_for
from ..security import require_api_key
from .. import repositories

router = APIRouter(dependencies=[Depends(require_api_key)])


@router.post("/api/screenings", status_code=201, tags=["screenings"])
def save_screening(payload: ScreeningSaveIn, db: Session = Depends(get_db)) -> dict:
    """Persist a screening result produced by the real MATLAB model."""

    screening = payload.screening

    patient = repositories.upsert_patient(
        db,
        patient_id=payload.patient.patientId,
        name=payload.patient.name,
        age=payload.patient.age,
        gender=payload.patient.gender,
    )

    from datetime import datetime

    screening_date = payload.screeningDate or datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    probability = screening.probabilities or {}
    evidence = screening.lesionEvidence or []
    quality = screening.imageQuality or {}

    record = repositories.create_screening(
        db,
        patient_id=patient.patient_id,
        screening_date=screening_date,
        predicted_class=screening.predictedClass,
        risk_level=getattr(screening, "riskLevel", None) or risk_level_for(screening.predictedClass),
        confidence=screening.confidence,
        confidence_status=screening.confidenceStatus,
        referral_status=screening.referralStatus,
        recommendation=screening.recommendation,
        screening_status=getattr(screening, "screeningStatus", None)
        or screening_status_for(screening.qualityStatus, screening.referralStatus),
        quality_status=screening.qualityStatus,
        quality_message=screening.qualityMessage,
        brightness=quality.get("brightness"),
        contrast=quality.get("contrast"),
        sharpness=quality.get("sharpness"),
        probabilities=probability,
        lesion_evidence=evidence,
    )
    db.commit()

    return {
        "status": "success",
        "operation": "save_screening",
        "patientId": patient.patient_id,
        "screeningId": record.screening_id,
        "screeningStatus": record.screening_status,
        "risk": record.risk_level,
        "screeningDate": record.screening_date,
        "message": "Patient and screening record saved successfully.",
    }


@router.get("/api/screenings", tags=["screenings"])
def list_screenings(
    limit: int = Query(default=200, ge=1, le=1000),
    db: Session = Depends(get_db),
) -> dict:
    rows = repositories.list_screenings(db, limit=limit)
    return {
        "status": "success",
        "operation": "get_screening_history",
        "count": len(rows),
        "screeningHistory": rows,
    }