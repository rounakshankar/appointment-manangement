FROM python:3.12-slim-bookworm

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml alembic.ini ./
COPY cacms ./cacms

RUN pip install --no-cache-dir .

EXPOSE 8000

# Run migrations then API (override in compose for one-off commands)
CMD ["sh", "-c", "alembic upgrade head && uvicorn cacms.main:app --host 0.0.0.0 --port 8000"]
