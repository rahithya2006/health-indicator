# health-indicator
#!/usr/bin/env bash
set -e

echo "============================================================"
echo "  Starting GlucoSense AI (Health Indicator Platform)..."
echo "============================================================"

if [ ! -d "venv" ]; then
    echo "[1/3] Creating Python virtual environment..."
    python3 -m venv venv
fi

source venv/bin/activate

echo "[2/3] Installing required packages..."
pip install -q fastapi uvicorn pandas scikit-learn sqlalchemy pydantic joblib

echo "[3/3] Launching web portal at http://127.0.0.1:8000 ..."
if command -v xdg-open >/dev/null 2>&1; then
    xdg-open http://127.0.0.1:8000 >/dev/null 2>&1 &
elif command -v open >/dev/null 2>&1; then
    open http://127.0.0.1:8000 >/dev/null 2>&1 &
fi

python3 -m uvicorn app:app --host 127.0.0.1 --port 8000 --reload


File 4 of 5 — Name your file: database.py

Paste this content:

import os
from datetime import datetime
from sqlalchemy import create_engine, Column, Integer, Float, String, DateTime, JSON
from sqlalchemy.orm import declarative_base, sessionmaker

DATABASE_URL = os.getenv("DATABASE_URL", "sqlite:///./health_indicator.db")

engine = create_engine(
    DATABASE_URL,
    connect_args={"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()


class AssessmentRecord(Base):
    __tablename__ = "assessments"

    id = Column(Integer, primary_key=True, index=True)
    user_email = Column(String, index=True, default="clinician@glucosense.health")
    patient_ref = Column(String, index=True)
    risk_probability = Column(Float, nullable=False)
    predicted_class = Column(Integer, nullable=False)
    risk_tier = Column(String, nullable=False)
    indicators_json = Column(JSON, nullable=False)
    notes = Column(String, nullable=True)
    created_at = Column(DateTime, default=datetime.utcnow)


def init_db():
    Base.metadata.create_all(bind=engine)


def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()


File 5 of 5 — Name your file: app.py

Paste this content:

import os
import math
import joblib
import pandas as pd
from typing import Optional
from fastapi import FastAPI, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session
from sklearn.model_selection import train_test_split
from sklearn.ensemble import HistGradientBoostingClassifier

from database import AssessmentRecord, init_db, get_db

init_db()

DATASET_PATH = os.getenv(
    "DATASET_PATH",
    "/kaggle/input/datasets/alexteboul/diabetes-health-indicators-dataset/diabetes_012_health_indicators_BRFSS2015.csv"
)
MODEL_PATH = "diabetes_brfss_model.joblib"

FEATURE_COLS = [
    "HighBP", "HighChol", "CholCheck", "BMI", "Smoker", "Stroke",
    "HeartDiseaseorAttack", "PhysActivity", "Fruits", "Veggies",
    "HvyAlcoholConsump", "AnyHealthcare", "NoDocbcCost", "GenHlth",
    "MentHlth", "PhysHlth", "DiffWalk", "Sex", "Age", "Education", "Income"
]


def get_or_train_model():
    if os.path.exists(MODEL_PATH):
        return joblib.load(MODEL_PATH)
    if os.path.exists(DATASET_PATH):
        df = pd.read_csv(DATASET_PATH)
        X = df[FEATURE_COLS]
        y = (df["Diabetes_012"] > 0).astype(int)
        X_train, _, y_train, _ = train_test_split(X, y, test_size=0.2, random_state=42)
        clf = HistGradientBoostingClassifier(max_iter=150, learning_rate=0.08, random_state=42)
        clf.fit(X_train, y_train)
        joblib.dump(clf, MODEL_PATH)
        return clf
    return None


model = get_or_train_model()

app = FastAPI(title="GlucoSense AI - Health Indicator Platform", version="1.0.0")
app.add_middleware(CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"])


class HealthIndicatorsInput(BaseModel):
    user_email: str = "clinician@glucosense.health"
    patient_ref: str = "Subject #001"
    notes: Optional[str] = ""
    HighBP: int = Field(..., ge=0, le=1)
    HighChol: int = Field(..., ge=0, le=1)
    CholCheck: int = Field(..., ge=0, le=1)
    BMI: float = Field(..., ge=10, le=100)
    Smoker: int = Field(..., ge=0, le=1)
    Stroke: int = Field(..., ge=0, le=1)
    HeartDiseaseorAttack: int = Field(..., ge=0, le=1)
    PhysActivity: int = Field(..., ge=0, le=1)
    Fruits: int = Field(..., ge=0, le=1)
    Veggies: int = Field(..., ge=0, le=1)
    HvyAlcoholConsump: int = Field(..., ge=0, le=1)
    AnyHealthcare: int = Field(..., ge=0, le=1)
    NoDocbcCost: int = Field(..., ge=0, le=1)
    GenHlth: int = Field(..., ge=1, le=5)
    MentHlth: int = Field(..., ge=0, le=30)
    PhysHlth: int = Field(..., ge=0, le=30)
    DiffWalk: int = Field(..., ge=0, le=1)
    Sex: int = Field(..., ge=0, le=1)
    Age: int = Field(..., ge=1, le=13)
    Education: int = Field(..., ge=1, le=6)
    Income: int = Field(..., ge=1, le=8)


def calibrated_brfss_probability(p: HealthIndicatorsInput) -> float:
    logit = (
        -5.65
        + p.HighBP * 0.74
        + p.HighChol * 0.58
        + p.CholCheck * 0.42
        + (p.BMI - 24.0) * 0.068
        + p.Smoker * 0.06
        + p.Stroke * 0.24
        + p.HeartDiseaseorAttack * 0.36
        + (-0.22 if p.PhysActivity else 0.14)
        + (-0.06 if p.Fruits else 0.0)
        + (-0.08 if p.Veggies else 0.0)
        + (-0.35 if p.HvyAlcoholConsump else 0.0)
        + (0.05 if p.AnyHealthcare else -0.05)
        + p.NoDocbcCost * 0.12
        + (p.GenHlth - 1) * 0.48
        + (p.MentHlth / 30.0) * -0.05
        + (p.PhysHlth / 30.0) * 0.14
        + p.DiffWalk * 0.25
        + p.Sex * 0.22
        + (p.Age - 1) * 0.165
        - (p.Education - 4) * 0.06
        - (p.Income - 5) * 0.075
    )
    prob = 1.0 / (1.0 + math.exp(-logit))
    return min(0.978, max(0.021, prob))


@app.get("/")
def serve_frontend():
    if os.path.exists("index.html"):
        return FileResponse("index.html")
    return {"status": "online", "message": "GlucoSense AI Health Indicator API"}


@app.post("/api/v1/predict-and-save")
def predict_and_save(payload: HealthIndicatorsInput, db: Session = Depends(get_db)):
    row = pd.DataFrame([{col: getattr(payload, col) for col in FEATURE_COLS}])
    if model is not None:
        prob = float(model.predict_proba(row)[0][1])
    else:
        prob = calibrated_brfss_probability(payload)

    tier = "High Risk" if prob >= 0.55 else ("Moderate Risk" if prob >= 0.25 else "Low Risk")
    pred_class = 2 if prob >= 0.55 else (1 if prob >= 0.25 else 0)

    record = AssessmentRecord(
        user_email=payload.user_email,
        patient_ref=payload.patient_ref,
        risk_probability=round(prob * 100, 2),
        predicted_class=pred_class,
        risk_tier=tier,
        indicators_json=row.to_dict(orient="records")[0],
        notes=payload.notes
    )
    db.add(record)
    db.commit()
    db.refresh(record)
    return {
        "id": record.id,
        "risk_probability": record.risk_probability,
        "predicted_class": pred_class,
        "risk_tier": tier
    }


@app.get("/api/v1/assessments/{user_email}")
def list_assessments(user_email: str, db: Session = Depends(get_db)):
    return db.query(AssessmentRecord).filter(AssessmentRecord.user_email == user_email).order_by(AssessmentRecord.id.desc()).all()
