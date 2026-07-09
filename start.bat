@echo off
REM Package Router — one-command startup (backend + frontend)
setlocal
cd /d "%~dp0"

echo.
echo  ┌─────────────────────────────────────┐
echo  │  Package Router — starting up...    │
echo  └─────────────────────────────────────┘
echo.

REM ---- backend deps ----
if not exist "backend\.venv" (
  echo [1/4] Creating Python virtual environment...
  python -m venv backend\.venv || goto :error
) else (
  echo [1/4] Python venv found.
)

echo [2/4] Installing backend dependencies (fast if cached)...
backend\.venv\Scripts\python -m pip install -q -r backend\requirements.txt || goto :error

REM ---- frontend deps ----
if not exist "frontend\node_modules" (
  echo [3/4] Installing frontend dependencies (first run only)...
  pushd frontend
  call npm install --silent || goto :error
  popd
) else (
  echo [3/4] Frontend dependencies found.
)

REM ---- launch ----
echo [4/4] Launching backend (:8000) and frontend (:5173)...
start "PackageRouter-Backend" cmd /c "cd backend && .venv\Scripts\python -m uvicorn app.main:app --port 8000"
start "PackageRouter-Frontend" cmd /c "cd frontend && npm run dev"

echo.
echo  ✔ Package Router is starting.
echo.
echo    Open:  http://localhost:5173
echo.
echo  (Close the two spawned terminal windows to stop.)
endlocal
exit /b 0

:error
echo.
echo  ✖ Startup failed — see output above.
endlocal
exit /b 1
