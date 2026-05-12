"""
Plan features configuration — single source of truth for all plan limits and feature flags.

No imports from the rest of the app. All enforcement logic reads from here.
"""

from typing import Optional

# Ordered from lowest to highest tier
PLAN_TIERS: list[str] = ["free", "starter", "clinic", "pro", "enterprise"]

# Per-plan feature dict.
# Numeric keys: None means unlimited.
# Boolean keys: False means the feature is not available on that plan.
PLAN_FEATURES: dict[str, dict] = {
    "free": {
        "max_doctors": 1,
        "max_staff": 3,
        "max_appointments_per_month": 200,
        "can_export_reports": False,
        "can_export_pdf": False,
        "multi_branch": False,
        "api_access": False,
        "lab_integrations": False,
    },
    "starter": {
        "max_doctors": 1,
        "max_staff": 5,
        "max_appointments_per_month": None,  # unlimited
        "can_export_reports": True,
        "can_export_pdf": False,
        "multi_branch": False,
        "api_access": False,
        "lab_integrations": False,
    },
    "clinic": {
        "max_doctors": 5,
        "max_staff": 10,
        "max_appointments_per_month": None,  # unlimited
        "can_export_reports": True,
        "can_export_pdf": True,
        "multi_branch": False,
        "api_access": False,
        "lab_integrations": True,
    },
    "pro": {
        "max_doctors": None,  # unlimited
        "max_staff": None,    # unlimited
        "max_appointments_per_month": None,  # unlimited
        "can_export_reports": True,
        "can_export_pdf": True,
        "multi_branch": True,
        "api_access": True,
        "lab_integrations": True,
    },
    "enterprise": {
        "max_doctors": None,  # unlimited
        "max_staff": None,    # unlimited
        "max_appointments_per_month": None,  # unlimited
        "can_export_reports": True,
        "can_export_pdf": True,
        "multi_branch": True,
        "api_access": True,
        "lab_integrations": True,
    },
}

# Monthly prices in INR (for display — not paise).
# enterprise is bespoke / contact-us pricing, so not listed here.
PLAN_MONTHLY_PRICES: dict[str, int] = {
    "free": 0,
    "starter": 999,
    "clinic": 2999,
    "pro": 7999,
}

# Required keys that every plan dict must contain.
REQUIRED_PLAN_KEYS: frozenset[str] = frozenset(PLAN_FEATURES["free"].keys())
