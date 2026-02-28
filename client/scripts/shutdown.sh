#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  OpenCat Portable - Shutdown"
echo "=========================================="
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE="$SCRIPT_DIR/tools/node/bin/node"
OPENCLAW_PORT="${OPENCLAW_PORT:-3080}"

# Tunnel registration always goes to Kuroneko (decoupled from LLM proxy config)
REGISTRATION_BASE="https://kuroneko.chat/opencat"

# Read token (for Bearer auth only)
TOKEN=""
if [[ -f "$SCRIPT_DIR/token.json" ]]; then
  TOKEN=$("$NODE" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(t.token)" "$SCRIPT_DIR/token.json" 2>/dev/null || true)
fi

# ---------- Step 1: Deregister tunnel ----------

if [[ -n "$TOKEN" ]]; then
  echo "[1/4] Deregistering tunnel from server..."
  "$NODE" -e "
    const https = require('https');
    const http = require('http');
    const url = new URL(process.argv[1] + '/api/tunnel');
    const mod = url.protocol === 'https:' ? https : http;
    const req = mod.request(url, {
      method: 'DELETE',
      headers: { 'Authorization': 'Bearer ' + process.argv[2] }
    }, (res) => {
      if (res.statusCode === 204) { console.log('    Tunnel deregistered.'); }
      else { let b=''; res.on('data',c=>b+=c); res.on('end',()=>console.log('    Response:',res.statusCode,b)); }
    });
    req.on('error', e => console.error('    Error:', e.message));
    req.end();
  " "$REGISTRATION_BASE" "$TOKEN" || true
  echo "[1/4] Done."
else
  echo "[1/4] Skipped (no token config)."
fi
echo

# ---------- Step 2: Stop Watchdog ----------

echo "[2/4] Stopping Watchdog..."
WATCHDOG_PID=$(pgrep -f "startup\.sh" 2>/dev/null || true)
if [[ -n "$WATCHDOG_PID" ]]; then
  echo "    Killing Watchdog PID $WATCHDOG_PID"
  kill $WATCHDOG_PID 2>/dev/null || true
  echo "    Watchdog stopped."
else
  echo "    Watchdog is not running."
fi
echo "[2/4] Done."
echo

# ---------- Step 3: Stop cloudflared ----------

echo "[3/4] Stopping cloudflared..."
if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
  pkill -f "cloudflared tunnel" 2>/dev/null || true
  echo "    cloudflared stopped."
else
  echo "    cloudflared is not running."
fi
echo "[3/4] Done."
echo

# ---------- Step 4: Stop OpenClaw ----------

echo "[4/4] Stopping OpenClaw on port $OPENCLAW_PORT..."
pid=$(lsof -ti :"$OPENCLAW_PORT" 2>/dev/null || true)
if [[ -n "$pid" ]]; then
  echo "    Killing PID $pid"
  kill -9 $pid 2>/dev/null || true
  echo "    OpenClaw stopped."
else
  echo "    OpenClaw is not running on port $OPENCLAW_PORT."
fi
echo "[4/4] Done."
echo

# ---------- Cleanup ----------

rm -f "$SCRIPT_DIR/_run_openclaw.sh" "$SCRIPT_DIR/_run_cloudflared.sh" 2>/dev/null || true

echo "=========================================="
echo "  All services stopped."
echo "=========================================="
