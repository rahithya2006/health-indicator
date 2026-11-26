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