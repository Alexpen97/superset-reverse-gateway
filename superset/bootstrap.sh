#!/bin/bash
set -euo pipefail

APP_ROOT="${SUPERSET_APP_ROOT:-/bi}"
export SUPERSET_CONFIG_PATH="${SUPERSET_CONFIG_PATH:-/app/pythonpath/superset_config.py}"
export FLASK_APP="${FLASK_APP:-superset.app:create_app(superset_app_root='${APP_ROOT}')}"
export HOME="${HOME:-/tmp}"

echo "[bootstrap] Installing OIDC / Postgres client deps via uv..."
# apache/superset:6.x uses a uv-managed venv at /app/.venv (no pip module).
if command -v uv >/dev/null 2>&1; then
  uv pip install --no-cache-dir \
    "authlib>=1.3.0,<1.6" \
    "psycopg2-binary>=2.9.9"
else
  /usr/local/bin/python -m pip install --no-cache-dir \
    "authlib>=1.3.0,<1.6" \
    "psycopg2-binary>=2.9.9"
fi
python -c "import authlib, psycopg2; print('[bootstrap] deps ok')"

echo "[bootstrap] Waiting for Postgres at ${SUPERSET_DB_HOST:-postgres}:${SUPERSET_DB_PORT:-5432}..."
python - <<'PY'
import os, socket, time, sys
host = os.environ.get("SUPERSET_DB_HOST", "postgres")
port = int(os.environ.get("SUPERSET_DB_PORT", "5432"))
for i in range(60):
    try:
        with socket.create_connection((host, port), timeout=3):
            print("[bootstrap] Postgres port is open.")
            sys.exit(0)
    except OSError as exc:
        print(f"[bootstrap] wait {i+1}/60: {exc}")
        time.sleep(2)
print("[bootstrap] Postgres did not become ready in time.", file=sys.stderr)
sys.exit(1)
PY

echo "[bootstrap] Running db upgrade..."
superset db upgrade

echo "[bootstrap] Ensuring local admin exists (fallback; primary auth is Keycloak)..."
superset fab create-admin \
  --username "${SUPERSET_ADMIN_USERNAME:-admin}" \
  --firstname Admin \
  --lastname User \
  --email "${SUPERSET_ADMIN_EMAIL:-admin@example.com}" \
  --password "${SUPERSET_ADMIN_PASSWORD:-admin}" \
  || true

echo "[bootstrap] Initializing roles/perms..."
superset init

echo "[bootstrap] Starting Superset with FLASK_APP=${FLASK_APP}..."
if [[ -x /usr/bin/run-server.sh ]]; then
  exec /usr/bin/run-server.sh
fi
exec gunicorn \
  --bind "0.0.0.0:8088" \
  --workers "${SERVER_WORKER_AMOUNT:-1}" \
  --timeout "${GUNICORN_TIMEOUT:-120}" \
  --limit-request-line 0 \
  --limit-request-field_size 0 \
  "${FLASK_APP}"
