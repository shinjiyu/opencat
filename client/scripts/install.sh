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

echo "[1/3] Checking Node..."
echo "[1/3] Checking Node" >> "$LOG_FILE"
"$NODE" --version
echo

# ---------- Step 2: npm install ----------

echo "[2/3] Installing dependencies..."
echo "[2/3] Installing dependencies" >> "$LOG_FILE"
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
echo "[2/3] Done."
echo

# ---------- Step 3: First-run setup ----------

echo "[3/3] Configuring OpenClaw gateway (first-run setup)..."
echo "[3/3] Configuring gateway" >> "$LOG_FILE"
if "$NODE" "$SCRIPT_DIR/configure-gateway.js"; then
  echo "[3/3] Done."
else
  echo "WARN: Gateway configuration failed. Check configure-gateway.js output."
  echo "WARN: configure-gateway failed" >> "$LOG_FILE"
fi
echo

echo "Install completed" >> "$LOG_FILE"

echo "=========================================="
echo "  Install complete. Starting services..."
echo "=========================================="
echo

# Auto-call startup script
exec "$SCRIPT_DIR/startup.sh"
