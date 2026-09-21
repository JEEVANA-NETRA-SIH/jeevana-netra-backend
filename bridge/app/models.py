"""SQLAlchemy models.

Tables replicate the data model produced by the original MATLAB
jeevana_patient_api.m so no existing fields are lost when persistence moves
into the bridge (Database Toolbox cannot be packaged with MATLAB Compiler).
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import ForeignKey, Index, Integer, String, Text, UniqueConstraint
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship


class Base(DeclarativeBase):
    pass


class Patient(Base):
    __tablename__ = "patients"

    patient_id: Mapped[str] = mapped_column(String(64), primary_key=True)
    name: Mapped[str] = mapped_column(String(200), nullable=False)
    age: Mapped[float | None] = mapped_column(nullable=True)
    gender: Mapped[str | None] = mapped_column(String(32), nullable=True)
    created_at: Mapped[str] = mapped_column(String(32), nullable=False)
    updated_at: Mapped[str] = mapped_column(String(32), nullable=False)

    screenings: Mapped[list["Screening"]] = relationship(
        back_populates="patient", cascade="all, delete-orphan"
    )


class Screening(Base):
    __tablename__ = "screenings"
    __table_args__ = (
        UniqueConstraint("screening_id", name="uq_screenings_screening_id"),
        Index("idx_screenings_patient", "patient_id"),
        Index("idx_screenings_date", "screening_date"),
    )

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    screening_id: Mapped[str] = mapped_column(String(32), nullable=False)
    patient_id: Mapped[str] = mapped_column(ForeignKey("patients.patient_id"), nullable=False)
    screening_date: Mapped[str] = mapped_column(String(32), nullable=False)

    predicted_class: Mapped[str] = mapped_column(String(64), nullable=False)
    risk_level: Mapped[str | None] = mapped_column(String(32), nullable=True)
    confidence: Mapped[float | None] = mapped_column(nullable=True)
    confidence_status: Mapped[str | None] = mapped_column(String(32), nullable=True)
    referral_status: Mapped[str | None] = mapped_column(String(64), nullable=True)
    recommendation: Mapped[str | None] = mapped_column(Text, nullable=True)
    screening_status: Mapped[str | None] = mapped_column(String(32), nullable=True)

    quality_status: Mapped[str | None] = mapped_column(String(32), nullable=True)
    quality_message: Mapped[str | None] = mapped_column(Text, nullable=True)
    brightness: Mapped[float | None] = mapped_column(nullable=True)
    contrast: Mapped[float | None] = mapped_column(nullable=True)
    sharpness: Mapped[float | None] = mapped_column(nullable=True)

    probabilities_json: Mapped[str | None] = mapped_column(Text, nullable=True)
    lesion_evidence_json: Mapped[str | None] = mapped_column(Text, nullable=True)

    patient: Mapped["Patient"] = relationship(back_populates="screenings")


def now_text() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")