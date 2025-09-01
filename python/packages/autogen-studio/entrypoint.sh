#!/usr/bin/env bash
# Assumptions: you're running inside a container with the repo bind-mounted to /work.
# - /work/autogen is the root of the repo cloned from GitHub (https://github.com/snj-edutech/autogen.git; https://github.com/microsoft/autogen.git)
# This script installs deps, builds the UI, and runs the FastAPI server with reload.
set -euo pipefail

# ---- Paths ----
REPO_ROOT="/work/autogen"
PYSPACE="$REPO_ROOT/python"
PKG_ROOT="$PYSPACE/packages"

if [[ ! -d "$PYSPACE" ]]; then
  echo "ERROR: Expected workspace at $PYSPACE (bind-mount your repo to /work)."
  exit 1
fi

# ---- 1) Install workspace deps (editable) ----
cd "$PYSPACE"
uv sync --all-extras

# Activate venv
source .venv/bin/activate

# Ensure uvicorn + watchfiles available (watchfiles => better reload)
python -m pip install -U pip
python -m pip install "uvicorn[standard]" watchfiles

# ---- 2) Build Gatsby UI and copy into FastAPI static dir ----
FRONTEND_DIR=""
if [[ -d "$PKG_ROOT/autogen-studio/frontend" ]]; then
  FRONTEND_DIR="$PKG_ROOT/autogen-studio/frontend"
elif [[ -d "$REPO_ROOT/samples/apps/autogen-studio/frontend" ]]; then
  FRONTEND_DIR="$REPO_ROOT/samples/apps/autogen-studio/frontend"
fi

if [[ -n "$FRONTEND_DIR" ]]; then
  export NVM_DIR="/root/.nvm"; . "$NVM_DIR/nvm.sh"
  cd "$FRONTEND_DIR"
  yarn install
  yarn build
  UI_TARGET="$PKG_ROOT/autogen-studio/autogenstudio/web/ui"
  mkdir -p "$UI_TARGET"
  rsync -a --delete "public/" "$UI_TARGET/"
else
  echo "WARNING: Could not find the autogen-studio frontend directory. Skipping UI build."
fi

# ---- 3) Ensure app data dir exists ----
mkdir -p "${AUTOGENSTUDIO_APPDIR}"

# ---- 4) Mirror the CLI's env-file behavior ----
ENV_FILE="${AUTOGENSTUDIO_APPDIR}/.env"
: > "$ENV_FILE"  # truncate/create

# Required/base vars
echo "AUTOGENSTUDIO_HOST=${AUTOGENSTUDIO_HOST:-0.0.0.0}" >> "$ENV_FILE"
echo "AUTOGENSTUDIO_PORT=${AUTOGENSTUDIO_PORT:-8080}"       >> "$ENV_FILE"
echo "AUTOGENSTUDIO_API_DOCS=${AUTOGENSTUDIO_API_DOCS:-True}" >> "$ENV_FILE"

# Optional vars (only if set)
if [[ -n "${AUTOGENSTUDIO_APPDIR:-}" ]]; then
  echo "AUTOGENSTUDIO_APPDIR=${AUTOGENSTUDIO_APPDIR}" >> "$ENV_FILE"
fi
if [[ -n "${AUTOGENSTUDIO_DATABASE_URI:-}" ]]; then
  echo "AUTOGENSTUDIO_DATABASE_URI=${AUTOGENSTUDIO_DATABASE_URI}" >> "$ENV_FILE"
fi
if [[ -n "${AUTOGENSTUDIO_AUTH_CONFIG:-}" ]]; then
  if [[ ! -f "${AUTOGENSTUDIO_AUTH_CONFIG}" ]]; then
    echo "Error: Auth config file not found: ${AUTOGENSTUDIO_AUTH_CONFIG}" >&2
    exit 1
  fi
  echo "AUTOGENSTUDIO_AUTH_CONFIG=${AUTOGENSTUDIO_AUTH_CONFIG}" >> "$ENV_FILE"
fi
if [[ -n "${AUTOGENSTUDIO_UPGRADE_DATABASE:-}" ]]; then
  echo "AUTOGENSTUDIO_UPGRADE_DATABASE=${AUTOGENSTUDIO_UPGRADE_DATABASE}" >> "$ENV_FILE"
fi
if [[ -n "${OPENAI_API_KEY:-}" ]]; then
  echo "OPENAI_API_KEY=${OPENAI_API_KEY}" >> "$ENV_FILE"
fi

# ---- 5) Run uvicorn (reload + explicit watched dirs) ----
# NOTE: uvicorn has no '--reload-backend' flag; with 'uvicorn[standard]' installed
# it automatically uses WatchFiles for reloading.
UV_HOST="${AUTOGENSTUDIO_HOST:-0.0.0.0}"
UV_PORT="${AUTOGENSTUDIO_PORT:-8080}"

# If AUTOGENSTUDIO_WORKERS is set, prefer multi-worker mode (no reload)
if [[ -n "${AUTOGENSTUDIO_WORKERS:-}" ]]; then
  # uvicorn: workers + env-file; reload is incompatible with workers>1
  exec uvicorn autogenstudio.web.app:app \
    --host "$UV_HOST" \
    --port "$UV_PORT" \
    --workers "${AUTOGENSTUDIO_WORKERS}" \
    --env-file "$ENV_FILE" \
    --log-level info
else
  # Default dev mode: single process + reload + watched dirs
  RELOAD_ARGS=(
    --reload
    --reload-dir "$PKG_ROOT/autogen-studio/autogenstudio"
    --reload-dir "$PKG_ROOT/autogen-agentchat/src"
    --reload-dir "$PKG_ROOT/autogen-core/src"
    --reload-dir "$PKG_ROOT/autogen-ext/src"
    --reload-exclude "**/alembic/*"
    --reload-exclude "**/alembic.ini"
    --reload-exclude "**/versions/*"
    --env-file "$ENV_FILE"
    --log-level info
  )
  exec uvicorn autogenstudio.web.app:app \
    --host "$UV_HOST" \
    --port "$UV_PORT" \
    "${RELOAD_ARGS[@]}"
fi
