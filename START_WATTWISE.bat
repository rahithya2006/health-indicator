@echo off
title GlucoSense AI - Health Indicator Platform
echo ============================================================
echo   Starting GlucoSense AI (Health Indicator Platform)...
echo ============================================================

if not exist venv (
    echo [1/3] Creating Python virtual environment...
    python -m venv venv
)

call venv\Scripts\activate.bat

echo [2/3] Installing required packages...
pip install -q fastapi uvicorn pandas scikit-learn sqlalchemy pydantic joblib

echo [3/3] Launching web portal at http://127.0.0.1:8000 ...
start "" http://127.0.0.1:8000
python -m uvicorn app:app --host 127.0.0.1 --port 8000 --reload