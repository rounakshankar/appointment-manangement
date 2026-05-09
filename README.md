# CACMS — Clinic Appointment & Consultation Management System

A comprehensive clinic management system with real-time queue management, appointment scheduling, consultation tracking, and payment processing. Built with a FastAPI backend and Flutter mobile app for seamless clinic operations.

## Features

### Backend (FastAPI + PostgreSQL)
- **User Management**: Role-based access for owners, admins, doctors, and receptionists
- **Patient Management**: Registration, consent tracking, and patient history
- **Appointment Scheduling**: Doctor-specific queues with priority handling (emergency appointments)
- **Consultation Management**: Service billing, diagnosis recording, and follow-up scheduling
- **Payment Processing**: Multiple payment modes with receipt generation
- **Real-time Events**: Server-sent events for live queue updates
- **Reports & Exports**: Comprehensive reporting and data export capabilities
- **Audit Logging**: Full activity tracking for compliance

### Flutter Mobile App
- **Admin Dashboard**: Complete clinic management interface
- **Doctor Interface**: Queue management and consultation recording
- **Patient Portal**: Live queue status and appointment booking via OTP
- **Real-time Updates**: Live SSE-based notifications
- **Offline Support**: Secure token storage and offline capabilities

## Tech Stack

- **Backend**: Python 3.10+, FastAPI, SQLAlchemy, Alembic, PostgreSQL
- **Frontend**: Flutter (Dart), Material Design 3
- **Authentication**: JWT + OTP for patient access
- **Real-time**: Server-Sent Events (SSE)
- **Deployment**: Docker-ready, cloud deployment checklists included

## Prerequisites

- Python 3.10 or higher
- PostgreSQL 13+
- Flutter SDK 3.0+
- Dart SDK
- Git

## Installation & Setup

### Backend Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/rounakshankar/appointment-manangement.git
   cd appointment-manangement
   ```

2. **Set up Python environment**
   ```bash
   cd cacms
   python -m venv venv
   # On Windows
   venv\Scripts\activate
   # On macOS/Linux
   source venv/bin/activate
   pip install -e ".[dev]"
   ```

3. **Database setup**
   ```bash
   # Copy and edit environment file
   cp .env.example .env
   # Edit .env with your DATABASE_URL

   # Run database migrations
   alembic upgrade head

   # Seed initial data (optional)
   python ../seed_doctors.py
   ```

4. **Start the backend server**
   ```bash
   uvicorn cacms.main:app --reload
   ```
   Server will be available at `http://localhost:8000`

### Flutter App Setup

1. **Install Flutter dependencies**
   ```bash
   cd cacms_flutter
   flutter pub get
   ```

2. **Configure API endpoint**
   - Update the base URL in the app configuration to point to your backend
   - Default: `http://localhost:8000`

3. **Run the app**
   ```bash
   flutter run
   ```

## Usage

### Admin Operations
- Login with admin credentials
- Manage doctors, services, and staff
- View live queues and manage appointments
- Generate reports and export data

### Doctor Workflow
- Login with doctor credentials
- View assigned queue
- Record consultations and services
- Process payments

### Patient Access
- Enter phone number for OTP verification
- View current queue position
- Receive real-time updates

## API Documentation

Once the backend is running, visit `http://localhost:8000/docs` for interactive API documentation.

## Project Structure

```
appointment-manangement/
├── cacms/                    # FastAPI backend
│   ├── main.py              # Application entry point
│   ├── config.py            # Configuration
│   ├── database.py          # Database connection
│   ├── models/              # SQLAlchemy models
│   ├── schemas/             # Pydantic schemas
│   ├── routers/             # API endpoints
│   ├── services/            # Business logic
│   └── middleware/          # Custom middleware
├── cacms_flutter/           # Flutter mobile app
│   ├── lib/
│   │   ├── core/            # Shared utilities
│   │   ├── features/        # Feature modules
│   │   └── main.dart        # App entry point
│   └── pubspec.yaml
├── scripts/                 # Utility scripts
├── tests/                   # Test suites
└── README.md
```

## Development

### Running Tests
```bash
# Backend tests
cd cacms
pytest

# Flutter tests
cd cacms_flutter
flutter test
```

### Code Quality
- Backend: Black, isort, flake8
- Flutter: flutter analyze

## Deployment

See `CLOUD_DEPLOYMENT_CHECKLIST.md` and `DEPLOYMENT_SPEC_SHEET.md` for detailed deployment instructions.

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests
5. Submit a pull request

## Support

For questions or issues, please open an issue on GitHub or contact the development team.
