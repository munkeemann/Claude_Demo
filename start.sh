#!/usr/bin/env bash
# Package Router — one-command startup (backend + frontend)
set -e
cd "$(dirname "$0")"

echo ""
echo "  Package Router — starting up..."
echo ""

# ---- backend deps ----
if [ ! -d backend/.venv ]; then
  echo "[1/4] Creating Python virtual environment..."
  python3 -m venv backend/.venv || python -m venv backend/.venv
else
  echo "[1/4] Python venv found."
fi

PY=backend/.venv/bin/python
[ -f "$PY" ] || PY=backend/.venv/Scripts/python

echo "[2/4] Installing backend dependencies (fast if cached)..."
"$PY" -m pip install -q -r backend/requirements.txt

# ---- frontend deps ----
if [ ! -d frontend/node_modules ]; then
  echo "[3/4] Installing frontend dependencies (first run only)..."
  (cd frontend && npm install --silent)
else
  echo "[3/4] Frontend dependencies found."
fi

# ---- launch ----
echo "[4/4] Launching backend (:8000) and frontend (:5173)..."
(cd backend && "../$PY" -m uvicorn app.main:app --port 8000) &
BACK_PID=$!
(cd frontend && npm run dev) &
FRONT_PID=$!

echo ""
echo "  ✔ Package Router is running."
echo ""
echo "    Open:  http://localhost:5173"
echo ""
trap "kill $BACK_PID $FRONT_PID 2>/dev/null" EXIT
wait
