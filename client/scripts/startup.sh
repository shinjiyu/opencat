#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  OpenCat Portable - Startup"
echo "=========================================="
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE="$SCRIPT_DIR/tools/node/bin/node"
NPM="$SCRIPT_DIR/tools/node/bin/npm"
APP_DIR="$SCRIPT_DIR/lib/app"
CLOUDFLARED="$SCRIPT_DIR/tools/cloudflared/cloudflared"
OPENCLAW_PORT="${OPENCLAW_PORT:-3080}"
TUNNEL_LOG="$SCRIPT_DIR/cloudflared.log"
WATCHDOG_INTERVAL=30

# Read token config
TOKEN=$("$NODE" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(t.token)" "$SCRIPT_DIR/token.json")
SERVER_BASE=$("$NODE" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const u=new URL(t.proxy_base_url);console.log(u.origin+u.pathname.replace(/\/v1\/?$/,''))" "$SCRIPT_DIR/token.json")

if [[ -z "$TOKEN" ]]; then
  echo "ERROR: Could not read token from token.json"
  exit 1
fi

# ---------- Helper: kill old processes ----------

kill_old_processes() {
  # Kill cloudflared
  pkill -f "cloudflared tunnel" 2>/dev/null || true

  # Kill OpenClaw on our port
  local pid
  pid=$(lsof -ti :"$OPENCLAW_PORT" 2>/dev/null || true)
  if [[ -n "$pid" ]]; then
    echo "    Killing process $pid on port $OPENCLAW_PORT"
    kill -9 $pid 2>/dev/null || true
  fi
  sleep 1
}

# ---------- Helper: parse tunnel URL from log ----------

parse_tunnel_url() {
  "$NODE" -e "try{const l=require('fs').readFileSync(process.argv[1],'utf8');const m=l.match(/https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com/);if(m)console.log(m[0])}catch(e){}" "$TUNNEL_LOG" 2>/dev/null || true
}

# ---------- Helper: register tunnel ----------

register_tunnel() {
  local tunnel_url="$1"
  "$NODE" -e "
    const https = require('https');
    const http = require('http');
    const url = new URL(process.argv[1] + '/api/tunnel');
    const mod = url.protocol === 'https:' ? https : http;
    const data = JSON.stringify({ tunnel_url: process.argv[2] });
    const req = mod.request(url, {
      method: 'PUT',
      headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data), 'Authorization': 'Bearer ' + process.argv[3] }
    }, (res) => {
      let body = '';
      res.on('data', c => body += c);
      res.on('end', () => {
        if (res.statusCode === 200) { const r = JSON.parse(body); console.log('    OpenClaw URL: ' + r.openclaw_url); }
        else { console.error('    Registration failed (' + res.statusCode + '): ' + body); }
      });
    });
    req.on('error', e => console.error('    Error: ' + e.message));
    req.write(data);
    req.end();
  " "$SERVER_BASE" "$tunnel_url" "$TOKEN"
}

# ---------- Helper: start cloudflared and wait for URL ----------

start_tunnel() {
  rm -f "$TUNNEL_LOG"
  nohup "$CLOUDFLARED" tunnel --url "http://127.0.0.1:$OPENCLAW_PORT" > "$TUNNEL_LOG" 2>&1 &
  CF_PID=$!

  TUNNEL_URL=""
  echo "    Waiting for tunnel URL..."
  for i in $(seq 1 30); do
    sleep 1
    TUNNEL_URL=$(parse_tunnel_url)
    if [[ -n "$TUNNEL_URL" ]]; then
      break
    fi
  done

  if [[ -z "$TUNNEL_URL" ]]; then
    echo "WARN: Could not detect tunnel URL within 30s."
    echo "     Check $TUNNEL_LOG for details."
    return 1
  fi
  echo "    Tunnel: $TUNNEL_URL"
  return 0
}

# ---------- Step 1: Kill old instances ----------

echo "[1/4] Stopping old instances..."
kill_old_processes
echo "[1/4] Done."
echo

# ---------- Step 2: Start OpenClaw ----------

echo "[2/4] Starting OpenClaw gateway on port $OPENCLAW_PORT..."

# Configure gateway for local mode + trusted-proxy access
"$NODE" "$SCRIPT_DIR/configure-gateway.js" >/dev/null 2>&1
echo "    Gateway config OK"

(nohup "$NODE" openclaw.mjs gateway run --port "$OPENCLAW_PORT" --bind loopback --no-color > "$SCRIPT_DIR/openclaw.log" 2>&1 &)
cd "$SCRIPT_DIR"

READY=0
for i in $(seq 1 15); do
  sleep 1
  if "$NODE" -e "const h=require('http');h.get('http://127.0.0.1:$OPENCLAW_PORT/__openclaw__/canvas/',r=>{process.exit(r.statusCode>=200&&r.statusCode<400?0:1)}).on('error',()=>process.exit(1))" 2>/dev/null; then
    READY=1
    break
  fi
done

if [[ "$READY" -eq 0 ]]; then
  echo "WARN: OpenClaw did not respond within 15s. Continuing anyway..."
  echo "     Check $SCRIPT_DIR/openclaw.log for details."
else
  echo "    OpenClaw gateway running on ws://127.0.0.1:$OPENCLAW_PORT"
fi
echo "[2/4] Done."
echo

# ---------- Step 3: Start cloudflared tunnel ----------

echo "[3/4] Starting cloudflared tunnel..."
TUNNEL_URL=""
HAS_TUNNEL=false

if [[ ! -x "$CLOUDFLARED" ]]; then
  echo "WARN: cloudflared not found at $CLOUDFLARED"
  echo "     Skipping tunnel. OpenClaw is accessible locally only."
else
  if start_tunnel; then
    HAS_TUNNEL=true
    echo "[3/4] Done."
    echo

    # ---------- Step 4: Register tunnel ----------

    echo "[4/4] Registering tunnel with server..."
    register_tunnel "$TUNNEL_URL"
    echo "[4/4] Done."
  fi
fi
echo

if $HAS_TUNNEL; then
  echo "=========================================="
  echo "  All services running"
  echo "=========================================="
  echo
  echo "  OpenClaw (tunnel):    $TUNNEL_URL"
  echo "  OpenClaw (redirect):  $SERVER_BASE/openclaw?token=$TOKEN"
  echo "  OpenClaw (local):     http://localhost:$OPENCLAW_PORT"
  echo
  echo "  Tunnel watchdog is active (every ${WATCHDOG_INTERVAL}s)."
  echo "  Press Ctrl+C to stop watchdog."
  echo "=========================================="
  echo
else
  echo "=========================================="
  echo "  OpenClaw running (no tunnel)"
  echo "=========================================="
  echo
  echo "  OpenClaw (local):     http://localhost:$OPENCLAW_PORT"
  echo
  echo "=========================================="
  exit 0
fi

# ---------- Watchdog: monitor tunnel health ----------

trap 'echo "Watchdog stopped."; exit 0' INT TERM

FAIL_COUNT=0

while true; do
  sleep "$WATCHDOG_INTERVAL"

  # Check if cloudflared process is alive
  if ! pgrep -f "cloudflared tunnel" >/dev/null 2>&1; then
    echo "[Watchdog $(date +%H:%M:%S)] cloudflared process died. Restarting..."
    FAIL_COUNT=0
    if start_tunnel; then
      echo "[Watchdog $(date +%H:%M:%S)] New tunnel: $TUNNEL_URL"
      register_tunnel "$TUNNEL_URL"
    else
      echo "[Watchdog $(date +%H:%M:%S)] Failed to restart tunnel. Will retry..."
    fi
    continue
  fi

  # Check if tunnel URL is reachable
  if "$NODE" -e "const h=require('https');h.get(process.argv[1],{timeout:10000},(r)=>{process.exit(r.statusCode>=200&&r.statusCode<500?0:1)}).on('error',()=>process.exit(1))" "$TUNNEL_URL" 2>/dev/null; then
    if [[ "$FAIL_COUNT" -gt 0 ]]; then
      echo "[Watchdog $(date +%H:%M:%S)] Tunnel recovered."
      FAIL_COUNT=0
    fi
  else
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "[Watchdog $(date +%H:%M:%S)] Tunnel unreachable (attempt $FAIL_COUNT/3)"
    if [[ "$FAIL_COUNT" -ge 3 ]]; then
      echo "[Watchdog $(date +%H:%M:%S)] 3 consecutive failures. Restarting tunnel..."
      pkill -f "cloudflared tunnel" 2>/dev/null || true
      sleep 2
      FAIL_COUNT=0
      if start_tunnel; then
        echo "[Watchdog $(date +%H:%M:%S)] New tunnel: $TUNNEL_URL"
        register_tunnel "$TUNNEL_URL"
      else
        echo "[Watchdog $(date +%H:%M:%S)] Failed to restart tunnel. Will retry..."
      fi
    fi
  fi
done
