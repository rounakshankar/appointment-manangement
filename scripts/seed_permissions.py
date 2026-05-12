"""
Seed permissions and role permissions for the RBAC system.
"""

import asyncio
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from cacms.database import AsyncSessionLocal
from cacms.models.permission import Permission, RolePermission


PERMISSIONS = [
    # Patient management
    ("view_patients", "View patient records"),
    ("create_patients", "Create new patient records"),
    ("edit_patients", "Edit patient information"),

    # Appointment management
    ("view_appointments", "View appointments"),
    ("create_appointments", "Create new appointments"),
    ("edit_appointments", "Edit appointment details"),
    ("edit_appointment_status", "Change appointment status"),
    ("view_own_appointments", "View own appointments only"),
    ("edit_own_appointments", "Edit own appointments only"),

    # Doctor management
    ("view_doctors", "View doctor records"),
    ("create_doctors", "Create new doctor records"),
    ("edit_doctors", "Edit doctor information"),

    # Service management
    ("view_services", "View services"),
    ("create_services", "Create new services"),
    ("edit_services", "Edit service information"),

    # Consultations
    ("record_consultations", "Record consultation notes"),
    ("view_own_patients", "View patients assigned to doctor"),

    # Billing and payments
    ("view_billing", "View billing information"),
    ("create_payments", "Record payments"),
    ("edit_payments", "Edit payment records"),

    # Reports
    ("view_reports", "View reports and analytics"),
    ("view_archived_reports", "View archived consultation reports"),

    # User management
    ("view_users", "View user accounts"),
    ("create_users", "Create new user accounts"),
    ("edit_users", "Edit user accounts"),

    # System
    ("view_logs", "View system logs"),
    ("manage_backup", "Manage backups"),
]


ROLE_PERMISSIONS = {
    "owner": [
        "view_patients", "create_patients", "edit_patients",
        "view_appointments", "create_appointments", "edit_appointments", "edit_appointment_status",
        "view_doctors", "create_doctors", "edit_doctors",
        "view_services", "create_services", "edit_services",
        "record_consultations", "view_own_patients",
        "view_billing", "create_payments", "edit_payments",
        "view_reports", "view_archived_reports",
        "view_users", "create_users", "edit_users",
        "view_logs", "manage_backup",
    ],
    "admin": [
        "view_patients", "create_patients", "edit_patients",
        "view_appointments", "create_appointments", "edit_appointments", "edit_appointment_status",
        "view_doctors", "create_doctors", "edit_doctors",
        "view_services", "create_services", "edit_services",
        "view_billing", "create_payments", "edit_payments",
        "view_reports",
        "view_users", "create_users", "edit_users",
    ],
    "doctor": [
        "view_own_patients",
        "view_own_appointments", "edit_own_appointments",
        "record_consultations",
        "view_archived_reports",
    ],
    "doc_assistant": [
        "view_appointments", "create_appointments", "edit_appointment_status",
        "view_patients",  # Limited view for appointment management
    ],
    "receptionist": [
        "view_patients", "create_patients", "edit_patients",
        "view_appointments", "create_appointments", "edit_appointments", "edit_appointment_status",
        "view_services",
        "view_billing", "create_payments",
    ],
}


async def seed_permissions():
    async with AsyncSessionLocal() as db:
        # Create permissions
        permission_map = {}
        for name, description in PERMISSIONS:
            result = await db.execute(select(Permission).where(Permission.name == name))
            permission = result.scalar_one_or_none()
            if permission is None:
                permission = Permission(name=name, description=description)
                db.add(permission)
                await db.flush()
            permission_map[name] = permission.permission_id

        # Create role permissions
        for role, perm_names in ROLE_PERMISSIONS.items():
            for perm_name in perm_names:
                if perm_name not in permission_map:
                    print(f"Warning: Permission {perm_name} not found, skipping")
                    continue

                result = await db.execute(
                    select(RolePermission).where(
                        RolePermission.role == role,
                        RolePermission.permission_id == permission_map[perm_name],
                        RolePermission.clinic_id.is_(None)  # Global permissions
                    )
                )
                if result.scalar_one_or_none() is None:
                    role_perm = RolePermission(
                        role=role,
                        permission_id=permission_map[perm_name],
                        clinic_id=None  # Global
                    )
                    db.add(role_perm)

        try:
            await db.commit()
            print("Permissions seeded successfully")
        except IntegrityError as e:
            await db.rollback()
            print(f"Error seeding permissions: {e}")


if __name__ == "__main__":
    asyncio.run(seed_permissions())