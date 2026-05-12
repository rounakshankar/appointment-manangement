# CACMS Beta Setup Guide

## Backend

Start the server:
```bash
.venv/Scripts/uvicorn cacms.main:app --host 0.0.0.0 --port 8000 --reload
```

### Creating the first owner account

Use the `scripts/create_owner.py` script to create the initial clinic and owner user:

```bash
python scripts/create_owner.py \
  --username owner \
  --password "YourStrongPassword123!" \
  --clinic-name "Your Clinic Name"
```

To seed a default admin user (for development only):
```bash
python seed_admin.py
```

> **Note:** There are no hardcoded default passwords. All users must be created via the scripts above or via `POST /v1/auth/register-clinic`.

### Email / SMTP (optional)

When `SMTP_HOST` is not configured in `.env`, the system falls back to logging emails to the server console. This is the default dev mode — no SMTP setup needed to test the record request flow.

To enable real email delivery, add to `.env`:
```dotenv
EMAIL_FROM=noreply@yourclinic.com
SMTP_HOST=smtp.gmail.com
SMTP_PORT=587
SMTP_USERNAME=your@gmail.com
SMTP_PASSWORD=your_app_password
```

## Flutter App

### First-run configuration

On first launch, the Flutter app shows a **Server Setup Screen** where you enter the backend URL. This is the recommended way to configure the backend URL — no need to rebuild the APK for each environment.

Alternatively, you can bake the URL into the build:

```bash
# Android Emulator
flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8000

# Physical device (same Wi-Fi as server)
flutter run --dart-define=BACKEND_URL=http://YOUR_SERVER_IP:8000

# Release APK
flutter build apk --dart-define=BACKEND_URL=http://YOUR_SERVER_IP:8000
# APK at: build/app/outputs/flutter-apk/app-release.apk
```

## What's wired

| Feature | Status |
|---|---|
| Admin/Owner login | ✅ Real API |
| Doctor login (JWT + doctor info from API) | ✅ Real API |
| Patient registration | ✅ Real API |
| Patient lookup by phone | ✅ Real API |
| Doctor list (admin dropdown) | ✅ Real API (`/v1/doctors`) |
| Appointment creation (normal/follow-up/emergency) | ✅ Real API |
| Doctor queue dashboard | ✅ Real API + SSE live updates |
| Call Next (atomic queue advancement) | ✅ Real API |
| No-show / Cancellation | ✅ Real API |
| Consultation recording + services | ✅ Real API |
| Follow-up prompt + booking | ✅ Real API |
| Payment recording | ✅ Real API |
| Services catalog | ✅ Real API |
| SSE reconnection with Last-Event-ID | ✅ Real API |
| Public queue display (no login) | ✅ Real API (`/v1/public/queue/{clinic_id}/{doctor_id}`) |
| Patient record request by email | ✅ Real API (`/v1/public/request-records`) |
| Clinic settings (owner) | ✅ Real API (`/v1/clinic`) |
| Plan & billing info (owner) | ✅ Real API (`/v1/billing/plans`, `/v1/billing/status`) |
| Super-admin plan activation | ✅ Real API (`/v1/superadmin/clinics/{id}/plan`) |

## Patient flow (no OTP login)

Patients **never log in**. The new patient flow is:

1. **Queue visibility** — staff share a QR code or URL: `http://YOUR_SERVER/v1/public/queue/{clinic_id}/{doctor_id}`
   - Shows current queue number, patients ahead, estimated wait
   - Live updates via SSE — no login required

2. **Medical records** — patient visits `POST /v1/public/request-records` with their phone number and an email address
   - System emails the last 5 consultation summaries to the provided address
   - Always returns the same response regardless of whether the patient exists (prevents phone enumeration)
   - Rate-limited to 3 requests per phone number per hour

## Billing workflow (no payment gateway)

1. Clinic owner contacts you (WhatsApp / email)
2. You receive payment (cash or UPI scan)
3. You activate their plan via the super-admin API:

```bash
curl -X PATCH http://YOUR_SERVER/v1/superadmin/clinics/{clinic_id}/plan \
  -H "Authorization: Bearer YOUR_SUPERADMIN_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "plan": "starter",
    "plan_status": "active",
    "plan_expires_at": "2026-06-10T00:00:00Z",
    "plan_note": "Paid Rs 999 via UPI ref TXN123 on 10-May-2026"
  }'
```

## Known beta limitations

- No payment gateway — plans are activated manually via super-admin API
- Email delivery requires SMTP configuration (falls back to console logging in dev)
- Flutter QR code sharing (task 18.6) requires `qr_flutter` package — add to pubspec.yaml when needed
