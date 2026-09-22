"""Derived screening fields.

These functions mirror the logic in the original MATLAB
jeevana_patient_api.m (determineRiskLevel / determineScreeningStatus) so the
bridge database produces identical values to what the MATLAB patient API
would have stored.
"""

from __future__ import annotations

from datetime import datetime

REFERABLE_DR = "REFERABLE DR"
NON_REFERABLE_DR = "NON-REFERABLE DR"


def risk_level_for(predicted_class: str | None) -> str:
    if not predicted_class or predicted_class in ("Not available", "RETAKE REQUIRED"):
        return "Unassessed"
    if predicted_class == "Mild":
        return "Medium"
    if predicted_class in ("Moderate", "Severe", "ProliferativeDR"):
        return "High"
    return "Low"


def screening_status_for(
    quality_status: str | None,
    referral_status: str | None,
) -> str:
    if quality_status != "Good":
        return "Pending"
    if referral_status == REFERABLE_DR:
        return "Requires Review"
    return "Completed"


def next_screening_number(existing_ids: list[str], year: str) -> int:
    """Return the next sequential screening number for the given year.

    Replicates the MATLAB generateScreeningId behaviour: JN-YYYY-###.
    A fresh 3-digit sequence starts at 001 for each year.
    """
    prefix = f"JN-{year}-"
    numbers = []
    for i in existing_ids:
        if i.startswith(prefix):
            suffix = i[len(prefix) :]
            if suffix.isdigit():
                numbers.append(int(suffix))
    return (max(numbers) + 1) if numbers else 1


def screening_year_for(screening_date: str | None) -> str:
    if screening_date and len(screening_date) >= 4 and screening_date[:4].isdigit():
        return screening_date[:4]
    return str(datetime.now().year)