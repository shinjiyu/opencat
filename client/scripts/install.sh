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
CLOUDFLARED="$SCRIPT_DIR/tools/cloudflared/cloudflared"
OPENCLAW_PORT="${OPENCLAW_PORT:-3080}"

if [[ ! -f "$APP_DIR/opencat.json" ]]; then
  echo "ERROR: This package is not pre-configured."
  exit 1
fi
if [[ ! -f "$SCRIPT_DIR/token.json" ]]; then
  echo "ERROR: token.json not found."
  exit 1
fi
if [[ ! -x "$NODE" ]]; then
  echo "ERROR: Node not found at $NODE"
  exit 1
fi

TOKEN=$("$NODE" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(t.token)" "$SCRIPT_DIR/token.json")
CHAT_URL=$("$NODE" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));console.log(t.chat_url)" "$SCRIPT_DIR/token.json")
SERVER_BASE=$("$NODE" -e "const t=JSON.parse(require('fs').readFileSync(process.argv[1],'utf8'));const u=new URL(t.chat_url);console.log(u.origin+u.pathname.replace(/\/chat$/,''))" "$SCRIPT_DIR/token.json")

echo "[1/5] Checking Node..."
"$NODE" --version
echo

echo "[2/5] Installing dependencies..."
cd "$APP_DIR"
set +e
"$NPM" install --omit=dev --ignore-scripts
NPM_EXIT=$?
set -e
cd "$SCRIPT_DIR"
if [[ "$NPM_EXIT" -ne 0 ]]; then
  echo "ERROR: npm install failed (exit $NPM_EXIT)."
  exit 1
fi
echo "[2/5] Done."
echo

echo "[3/5] Starting OpenClaw..."
cd "$APP_DIR"
(nohup "$NPM" start > "$SCRIPT_DIR/openclaw.log" 2>&1 &)
cd "$SCRIPT_DIR"
sleep 3
echo "[3/5] Done."
echo

echo "[4/5] Starting tunnel..."
TUNNEL_URL=""
if [[ ! -x "$CLOUDFLARED" ]]; then
  echo "WARN: cloudflared not found at $CLOUDFLARED"
  echo "     Skipping tunnel. You can manually set up a tunnel later."
else
  TUNNEL_LOG="$SCRIPT_DIR/cloudflared.log"
  nohup "$CLOUDFLARED" tunnel --url "http://127.0.0.1:$OPENCLAW_PORT" > "$TUNNEL_LOG" 2>&1 &
  CF_PID=$!

  echo "    Waiting for tunnel URL..."
  for i in $(seq 1 30); do
    sleep 1
    TUNNEL_URL=$("$NODE" -e "const fs=require('fs');try{const l=fs.readFileSync(process.argv[1],'utf8');const m=l.match(/https:\/\/[a-zA-Z0-9-]+\.trycloudflare\.com/);if(m)console.log(m[0])}catch(e){}" "$TUNNEL_LOG" 2>/dev/null || true)
    if [[ -n "$TUNNEL_URL" ]]; then
      break
    fi
  done

  if [[ -n "$TUNNEL_URL" ]]; then
    echo "    Tunnel URL: $TUNNEL_URL"
    echo "[4/5] Done."
    echo

    echo "[5/5] Registering tunnel with server..."
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
        if (res.statusCode === 200) { const r = JSON.parse(body); console.log('Registered. OpenClaw URL: ' + r.openclaw_url); }
        else { console.error('Registration failed (' + res.statusCode + '): ' + body); }
      });
    });
    req.on('error', e => console.error('Error: ' + e.message));
    req.write(data);
    req.end();
    " "$SERVER_BASE" "$TUNNEL_URL" "$TOKEN"
    echo "[5/5] Done."
  else
    echo "WARN: Could not detect tunnel URL within 30 seconds."
    echo "     Check $TUNNEL_LOG for details."
  fi
fi
echo

echo
echo "=========================================="
echo "  Installation complete!"
echo "=========================================="
echo
echo "  1. Remote Chat (server proxy):"
echo "     $CHAT_URL"
echo
if [[ -n "$TUNNEL_URL" ]]; then
  echo "  2. Local OpenClaw via tunnel:"
  echo "     $TUNNEL_URL"
  echo
  echo "     Or via kuroneko redirect:"
  echo "     $SERVER_BASE/openclaw?token=$TOKEN"
else
  echo "  2. Local OpenClaw (this machine only):"
  echo "     http://127.0.0.1:$OPENCLAW_PORT"
fi
echo
echo "=========================================="
