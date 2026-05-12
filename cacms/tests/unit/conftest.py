"""
Unit test configuration — sets required environment variables before any
module-level imports trigger Settings() validation.
"""

import os

# Must be set before cacms.config is imported
os.environ.setdefault(
    "JWT_SECRET",
    "unit-test-secret-do-not-use-in-production-min-32-chars-ok",
)
os.environ.setdefault("CORS_ORIGINS", "http://localhost:3000")
