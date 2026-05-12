"""
PlanEnforcer — stateless service that enforces plan limits and feature flags.

All methods are synchronous (no I/O). Reads from PLAN_FEATURES in cacms/config/plans.py.
"""

from __future__ import annotations

from fastapi import HTTPException

from cacms.config.plans import PLAN_FEATURES
from cacms.models.clinic import Clinic


class PlanEnforcer:
    """Enforce plan limits and feature flags for a clinic."""

    def get_plan_features(self, clinic: Clinic) -> dict:
        """Return the PLAN_FEATURES entry for the clinic's current plan.

        Falls back to 'free' if the plan name is unrecognised (defensive).
        """
        return PLAN_FEATURES.get(clinic.plan, PLAN_FEATURES["free"])

    def check_feature(self, clinic: Clinic, feature_name: str) -> None:
        """Raise HTTP 402 if the clinic's plan does not include *feature_name*.

        Args:
            clinic: The Clinic ORM instance (must have a ``plan`` attribute).
            feature_name: A boolean key from PLAN_FEATURES (e.g. ``'can_export_pdf'``).

        Raises:
            HTTPException(402): When the feature is ``False`` for the clinic's plan.
        """
        features = self.get_plan_features(clinic)
        if not features.get(feature_name, False):
            raise HTTPException(
                status_code=402,
                detail={
                    "error_code": "PLAN_LIMIT_EXCEEDED",
                    "message": (
                        f"Your {clinic.plan} plan does not include {feature_name}. "
                        "Upgrade your plan to access this feature."
                    ),
                    "detail": {
                        "resource": feature_name,
                        "limit": False,
                        "current": False,
                        "upgrade_url": "/v1/billing/plans",
                    },
                },
            )

    def check_limit(
        self,
        clinic: Clinic,
        resource_name: str,
        current_count: int,
    ) -> None:
        """Raise HTTP 402 if *current_count* is at or above the plan's limit.

        When the plan's limit for *resource_name* is ``None`` (unlimited), this
        method is a no-op regardless of *current_count*.

        Args:
            clinic: The Clinic ORM instance.
            resource_name: A numeric key from PLAN_FEATURES (e.g. ``'max_doctors'``).
            current_count: The current count of the resource for this clinic.

        Raises:
            HTTPException(402): When ``current_count >= limit`` and limit is not ``None``.
        """
        features = self.get_plan_features(clinic)
        limit = features.get(resource_name)

        # None means unlimited — always allow
        if limit is None:
            return

        if current_count >= limit:
            raise HTTPException(
                status_code=402,
                detail={
                    "error_code": "PLAN_LIMIT_EXCEEDED",
                    "message": (
                        f"Your {clinic.plan} plan allows up to {limit} {resource_name.replace('max_', '')}. "
                        "Upgrade your plan to add more."
                    ),
                    "detail": {
                        "resource": resource_name,
                        "limit": limit,
                        "current": current_count,
                        "upgrade_url": "/v1/billing/plans",
                    },
                },
            )


# Module-level singleton — import and use directly in routers/services.
plan_enforcer = PlanEnforcer()
