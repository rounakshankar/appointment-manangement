# CACMS — Clinic Appointment & Consultation Management System

## Backend (FastAPI + PostgreSQL)
cd cacms && pip install -e ".[dev]"
cp .env.example .env  # edit DATABASE_URL
alembic upgrade head
uvicorn cacms.main:app --reload

## Flutter
cd cacms_flutter && flutter pub get
flutter run
