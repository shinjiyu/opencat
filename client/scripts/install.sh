#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  OpenCat Portable - Install"
echo "=========================================="
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE="$SCRIPT_DIR/tools/node/bin/node"
NPM="$SCRIPT_DIR/tools/node/bin/npm"
APP_DIR="$SCRIPT_DIR/lib/app"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/install.log"

echo "[OpenCat Install] $(date)" > "$LOG_FILE"

# ---------- Pre-flight checks ----------

if [[ ! -f "$APP_DIR/opencat.json" ]]; then
  echo "ERROR: opencat.json not found - this package is not pre-configured."
  echo "ERROR: not pre-configured" >> "$LOG_FILE"
  exit 1
fi
if [[ ! -f "$SCRIPT_DIR/token.json" ]]; then
  echo "ERROR: token.json not found."
  echo "ERROR: token.json not found" >> "$LOG_FILE"
  exit 1
fi
if [[ ! -x "$NODE" ]]; then
  echo "ERROR: Bundled Node not found at $NODE"
  echo "ERROR: Node not found" >> "$LOG_FILE"
  exit 1
fi

# ---------- Step 1: Check Node ----------

echo "[1/2] Checking Node..."
echo "[1/2] Checking Node" >> "$LOG_FILE"
"$NODE" --version
echo

# ---------- Step 2: npm install ----------

echo "[2/2] Installing dependencies..."
echo "[2/2] Installing dependencies" >> "$LOG_FILE"
cd "$APP_DIR"
set +e
"$NPM" install --omit=dev --ignore-scripts
NPM_EXIT=$?
set -e
cd "$SCRIPT_DIR"
if [[ "$NPM_EXIT" -ne 0 ]]; then
  echo "ERROR: npm install failed (exit $NPM_EXIT)."
  echo "ERROR: npm install failed" >> "$LOG_FILE"
  exit 1
fi
echo "[2/2] Done."
echo

echo "Install completed" >> "$LOG_FILE"

echo "=========================================="
echo "  Install complete. Starting services..."
echo "=========================================="
echo

# Auto-call startup script
exec "$SCRIPT_DIR/startup.sh"
