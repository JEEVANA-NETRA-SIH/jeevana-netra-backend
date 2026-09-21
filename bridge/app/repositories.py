"""Persistence layer for patients and screenings.

All writes use SQLAlchemy's parameterized execution paths; no values are
string-interpolated into SQL.
"""

from __future__ import annotations

import json

from sqlalchemy import select
from sqlalchemy.orm import Session

from . import screening_logic
from .models import Patient, Screening, now_text


def _format_date_label(value: str | None) -> str:
    """ddd mmm yyyy label analogous to MATLAB formatDateLabel."""
    if not value:
        return ""
    try:
        from datetime import datetime

        return datetime.strptime(value, "%Y-%m-%d %H:%M:%S").strftime("%d %b %Y")
    except ValueError:
        return value


def upsert_patient(
    db: Session,
    patient_id: str,
    name: str,
    age: float | None,
    gender: str | None,
) -> Patient:
    patient = db.get(Patient, patient_id)
    timestamp = now_text()
    if patient is None:
        patient = Patient(
            patient_id=patient_id,
            name=name,
            age=age,
            gender=gender,
            created_at=timestamp,
            updated_at=timestamp,
        )
        db.add(patient)
    else:
        patient.name = name
        patient.age = age
        patient.gender = gender
        patient.updated_at = timestamp
    db.flush()
    return patient


def create_screening(
    db: Session,
    *,
    patient_id: str,
    screening_date: str,
    predicted_class: str,
    risk_level: str,
    confidence: float | None,
    confidence_status: str | None,
    referral_status: str | None,
    recommendation: str | None,
    screening_status: str,
    quality_status: str | None,
    quality_message: str | None,
    brightness: float | None,
    contrast: float | None,
    sharpness: float | None,
    probabilities: dict,
    lesion_evidence,
) -> Screening:
    year = screening_logic.screening_year_for(screening_date)
    existing = list(
        db.scalars(
            select(Screening.screening_id).where(Screening.screening_id.like(f"JN-{year}-%"))
        ).all()
    )
    number = screening_logic.next_screening_number(existing, year)
    screening_id = f"JN-{year}-{number:03d}"

    screening = Screening(
        screening_id=screening_id,
        patient_id=patient_id,
        screening_date=screening_date,
        predicted_class=predicted_class,
        risk_level=risk_level,
        confidence=confidence,
        confidence_status=confidence_status,
        referral_status=referral_status,
        recommendation=recommendation,
        screening_status=screening_status,
        quality_status=quality_status,
        quality_message=quality_message,
        brightness=brightness,
        contrast=contrast,
        sharpness=sharpness,
        probabilities_json=json.dumps(probabilities),
        lesion_evidence_json=json.dumps(lesion_evidence),
    )
    db.add(screening)
    db.flush()
    return screening


def list_screenings(db: Session, limit: int = 200) -> list[dict]:
    rows = db.execute(
        select(Screening, Patient)
        .join(Patient, Patient.patient_id == Screening.patient_id)
        .order_by(Screening.screening_date.desc(), Screening.id.desc())
        .limit(limit)
    ).all()

    result = []
    for screening, patient in rows:
        result.append(
            {
                "id": screening.screening_id,
                "patient": patient.name,
                "patientId": patient.patient_id,
                "result": screening.predicted_class,
                "risk": screening.risk_level,
                "confidence": screening.confidence,
                "date": _format_date_label(screening.screening_date),
                "status": screening.screening_status,
            }
        )
    return result


def get_patient_or_none(db: Session, patient_id: str) -> Patient | None:
    return db.get(Patient, patient_id)


def list_patients(db: Session, limit: int = 200) -> list[dict]:
    patients = db.scalars(
        select(Patient).order_by(Patient.created_at.desc()).limit(limit)
    ).all()

    result = []
    for patient in patients:
        latest = db.scalars(
            select(Screening)
            .where(Screening.patient_id == patient.patient_id)
            .order_by(Screening.screening_date.desc(), Screening.id.desc())
            .limit(1)
        ).first()

        result.append(
            {
                "id": patient.patient_id,
                "name": patient.name,
                "age": patient.age,
                "gender": patient.gender,
                "lastScreening": _format_date_label(latest.screening_date) if latest else None,
                "result": latest.predicted_class if latest else None,
                "risk": latest.risk_level if latest else None,
                "status": latest.screening_status if latest else None,
            }
        )
    return result


def get_patient_history(db: Session, patient_id: str) -> tuple[Patient | None, list[dict]]:
    patient = db.get(Patient, patient_id)
    if patient is None:
        return None, []

    rows = db.scalars(
        select(Screening)
        .where(Screening.patient_id == patient_id)
        .order_by(Screening.screening_date.asc(), Screening.id.asc())
    ).all()

    history = []
    for s in rows:
        def _maybe_json(value: str | None):
            if not value:
                return {}
            try:
                return json.loads(value)
            except (ValueError, TypeError):
                return {}

        history.append(
            {
                "screeningId": s.screening_id,
                "date": _format_date_label(s.screening_date),
                "result": s.predicted_class,
                "risk": s.risk_level or screening_logic.risk_level_for(s.predicted_class),
                "confidence": s.confidence,
                "confidenceStatus": s.confidence_status,
                "referralStatus": s.referral_status,
                "recommendation": s.recommendation,
                "qualityStatus": s.quality_status,
                "qualityMessage": s.quality_message,
                "brightness": s.brightness,
                "contrast": s.contrast,
                "sharpness": s.sharpness,
                "probabilities": _maybe_json(s.probabilities_json),
                "lesionEvidence": _maybe_json(s.lesion_evidence_json),
            }
        )
    return patient, history