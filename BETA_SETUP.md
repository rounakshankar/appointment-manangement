# CACMS Beta Setup Guide

## Backend

Start the server (already running on port 8000):
```bash
.venv/Scripts/uvicorn cacms.main:app --host 0.0.0.0 --port 8000 --reload
```

Default credentials:
- Admin: `admin` / `admin123`
- Doctor: `Dr. Sharma` / `any` (or Dr. Patel, Dr. Rao)
- Patient: OTP via phone number (OTP printed to server console — stub)

## Flutter App

### Android Emulator
```bash
flutter run --dart-define=BACKEND_URL=http://10.0.2.2:8000
```

### Physical Android/iOS Device (same Wi-Fi as server)
```bash
flutter run --dart-define=BACKEND_URL=http://10.218.231.247:8000
```

### Release APK for beta distribution
```bash
flutter build apk --dart-define=BACKEND_URL=http://10.218.231.247:8000
# APK at: build/app/outputs/flutter-apk/app-release.apk
```

## What's wired

| Feature | Status |
|---|---|
| Admin login | ✅ Real API |
| Doctor login (JWT + doctor info from API) | ✅ Real API |
| Patient OTP login | ✅ Real API (`/v1/auth/request-otp` → `/v1/auth/verify-otp`) |
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
| Patient live status (4 states) | ✅ Real API + SSE |
| Services catalog | ✅ Real API |
| SSE reconnection with Last-Event-ID | ✅ Real API |

## Known beta limitations

- OTP is printed to server console (no SMS gateway integrated yet)
- Doctor password is not enforced (any non-empty password works for MVP)
- Admin password is hardcoded (`admin123`) — change `ADMIN_PASSWORD_HASH` in `cacms/routers/auth.py` for production
