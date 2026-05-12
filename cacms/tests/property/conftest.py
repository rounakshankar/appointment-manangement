"""
Property test configuration — sets required environment variables before any
module-level imports trigger Settings() validation.
"""

import os

os.environ.setdefault(
    "JWT_SECRET",
    "property-test-secret-do-not-use-in-production-min-32-chars",
)
os.environ.setdefault("CORS_ORIGINS", "http://localhost:3000")
