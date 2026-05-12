"""
EmailService — async email delivery for patient record summaries.

Design decisions:
- Uses aiosmtplib for non-blocking SMTP; falls back to logging when SMTP is not configured.
- SMTP credentials are read from Settings at call time so hot-reload in tests works correctly.
- On SMTP error, logs the full exception and raises HTTP 502 so the caller can surface a
  meaningful error to the client without leaking internal details.
- The service is stateless — no instance state, all methods are async class methods so it
  can be used without instantiation.
"""

from __future__ import annotations

import logging
from datetime import date
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from typing import Any

from fastapi import HTTPException, status

from cacms.config import settings

logger = logging.getLogger(__name__)


class ConsultationSummary:
    """Lightweight data-transfer object for a single consultation's display fields.

    Attributes:
        consultation_id: UUID string of the consultation.
        date: The date the consultation was created.
        doctor_name: Display name of the treating doctor.
        symptoms: Patient-reported symptoms.
        diagnosis: Doctor's diagnosis text.
        notes: Optional additional notes.
        next_visit_date: Optional recommended follow-up date.
        services: List of service name strings rendered in the summary.
    """

    def __init__(
        self,
        consultation_id: str,
        date: date,
        doctor_name: str,
        symptoms: str,
        diagnosis: str,
        notes: str | None,
        next_visit_date: date | None,
        services: list[str],
    ) -> None:
        self.consultation_id = consultation_id
        self.date = date
        self.doctor_name = doctor_name
        self.symptoms = symptoms
        self.diagnosis = diagnosis
        self.notes = notes
        self.next_visit_date = next_visit_date
        self.services = services


def _build_visit_summary_text(
    patient_name: str,
    consultations: list[ConsultationSummary],
) -> str:
    """Render a plain-text email body for a list of consultation summaries."""
    lines: list[str] = [
        f"Medical Record Summary for {patient_name}",
        "=" * 48,
        "",
        "The following is a summary of your recent consultations.",
        "For full records, please contact your clinic directly.",
        "",
    ]

    for i, c in enumerate(consultations, start=1):
        lines += [
            f"Visit {i} — {c.date}",
            "-" * 40,
            f"Doctor     : {c.doctor_name}",
            f"Symptoms   : {c.symptoms}",
            f"Diagnosis  : {c.diagnosis}",
        ]
        if c.notes:
            lines.append(f"Notes      : {c.notes}")
        if c.next_visit_date:
            lines.append(f"Next Visit : {c.next_visit_date}")
        if c.services:
            lines.append("Services   :")
            for svc in c.services:
                lines.append(f"  - {svc}")
        lines.append("")

    lines += [
        "=" * 48,
        "This email was generated automatically by CACMS.",
        "Do not reply to this message.",
    ]
    return "\n".join(lines)


class EmailService:
    """Sends patient record summary emails via SMTP (aiosmtplib).

    When SMTP is not configured (``SMTP_HOST`` is empty), all send operations
    are silently skipped and the summary is logged at INFO level instead.
    """

    @staticmethod
    def _is_configured() -> bool:
        """Return True when all required SMTP settings are present."""
        return bool(settings.SMTP_HOST and settings.EMAIL_FROM)

    @staticmethod
    async def send_visit_summary(
        patient_email: str,
        patient_name: str,
        consultations: list[ConsultationSummary],
    ) -> None:
        """Send a plain-text email containing the patient's consultation summaries.

        Args:
            patient_email: Destination email address supplied by the patient.
            patient_name: Patient's display name used in the email greeting.
            consultations: Ordered list of ``ConsultationSummary`` objects (newest first).

        Raises:
            HTTPException(502): When SMTP is configured but delivery fails.
        """
        body = _build_visit_summary_text(patient_name, consultations)

        if not EmailService._is_configured():
            logger.info(
                "[EMAIL DEV] To: %s  Subject: Medical Record Summary\n%s",
                patient_email,
                body,
            )
            return

        # Build MIME message
        msg = MIMEMultipart("alternative")
        msg["Subject"] = f"Medical Record Summary — {patient_name}"
        msg["From"] = settings.EMAIL_FROM
        msg["To"] = patient_email
        msg.attach(MIMEText(body, "plain", "utf-8"))

        # Send via aiosmtplib
        try:
            import aiosmtplib  # imported lazily so the module loads without the package in dev

            await aiosmtplib.send(
                msg,
                hostname=settings.SMTP_HOST,
                port=settings.SMTP_PORT,
                username=settings.SMTP_USERNAME or None,
                password=settings.SMTP_PASSWORD or None,
                start_tls=True,
            )
            logger.info(
                "EmailService: sent visit summary to %s for patient %s",
                patient_email,
                patient_name,
            )
        except Exception as exc:
            logger.error(
                "EmailService: SMTP delivery failed to %s — %s",
                patient_email,
                exc,
                exc_info=True,
            )
            raise HTTPException(
                status_code=status.HTTP_502_BAD_GATEWAY,
                detail={
                    "error_code": "EMAIL_DELIVERY_FAILED",
                    "message": "Failed to deliver email. Please try again later.",
                },
            ) from exc
