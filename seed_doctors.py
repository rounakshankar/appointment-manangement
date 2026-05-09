"""Seed initial doctor records into the database."""
import asyncio
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from cacms.config import settings
from cacms.models.doctor import Doctor

async def seed():
    engine = create_async_engine(settings.DATABASE_URL)
    async_session = sessionmaker(engine, class_=AsyncSession, expire_on_commit=False)

    doctors = [
        Doctor(name="Dr. Sharma", specialization="General Medicine"),
        Doctor(name="Dr. Patel", specialization="Pediatrics"),
        Doctor(name="Dr. Rao", specialization="Cardiology"),
    ]

    async with async_session() as session:
        for doc in doctors:
            session.add(doc)
        await session.commit()
        print("Seeded 3 doctors:")
        for doc in doctors:
            print(f"  - {doc.name} ({doc.specialization})  id={doc.doctor_id}")

    await engine.dispose()

asyncio.run(seed())
