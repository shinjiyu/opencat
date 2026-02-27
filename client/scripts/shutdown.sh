#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  OpenCat Portable - Shutdown"
echo "=========================================="
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE="$SCRIPT_DIR/tools/node/bin/node"
OPENCLAW_PORT="${OPENCLAW_PORT:-3080}"

# Read token for tunnel deregistration
TOKEN=""
SERVER_BASE=""
if [[ -f "$SCRIPT_DIR/token.json" ]]; then
  TOKEN=$("$NODE" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(t.token)" "$SCRIPT_DIR/token.json" 2>/dev/null || true)
  SERVER_BASE=$("$NODE" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const u=new URL(t.proxy_base_url);console.log(u.origin+u.pathname.replace(/\/v1\/?$/,''))" "$SCRIPT_DIR/token.json" 2>/dev/null || true)
fi

# ---------- Step 1: Deregister tunnel ----------

if [[ -n "$TOKEN" && -n "$SERVER_BASE" ]]; then
  echo "[1/3] Deregistering tunnel from server..."
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
  " "$SERVER_BASE" "$TOKEN" || true
  echo "[1/3] Done."
else
  echo "[1/3] Skipped (no token or server config)."
fi
echo

# ---------- Step 2: Stop cloudflared ----------

echo "[2/3] Stopping cloudflared..."
if pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
  pkill -f "cloudflared tunnel" 2>/dev/null || true
  echo "    cloudflared stopped."
else
  echo "    cloudflared is not running."
fi
echo "[2/3] Done."
echo

# ---------- Step 3: Stop OpenClaw ----------

echo "[3/3] Stopping OpenClaw on port $OPENCLAW_PORT..."
pid=$(lsof -ti :"$OPENCLAW_PORT" 2>/dev/null || true)
if [[ -n "$pid" ]]; then
  echo "    Killing PID $pid"
  kill -9 $pid 2>/dev/null || true
  echo "    OpenClaw stopped."
else
  echo "    OpenClaw is not running on port $OPENCLAW_PORT."
fi
echo "[3/3] Done."
echo

# ---------- Cleanup ----------

rm -f "$SCRIPT_DIR/_run_openclaw.sh" "$SCRIPT_DIR/_run_cloudflared.sh" 2>/dev/null || true

echo "=========================================="
echo "  All services stopped."
echo "=========================================="
