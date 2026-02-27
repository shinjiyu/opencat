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

# --- Server URL (injected at build time) ---
SERVER_URL=${SERVER_URL:-https://proxy.example.com}

ARCH="$(uname -m)"
OS="$(uname -s)"
case "$OS-$ARCH" in
  Darwin-arm64)  PLATFORM="darwin-arm64" ;;
  Darwin-x86_64) PLATFORM="darwin-x64" ;;
  Linux-x86_64)  PLATFORM="linux-x64" ;;
  *)             PLATFORM="unknown" ;;
esac

if [[ -f "$APP_DIR/opencat.json" ]]; then
  echo "[INFO] Config already exists - pre-configured package detected."
  echo "[INFO] Skipping token request. Running npm install only."
  PRE_CONFIGURED=true
else
  PRE_CONFIGURED=false
fi

if [[ ! -x "$NODE" ]]; then
  echo "ERROR: Node not found at $NODE"
  echo "Please re-download the portable package for your platform."
  exit 1
fi

echo "[1/4] Checking Node..."
"$NODE" --version
echo

echo "[2/4] Installing dependencies..."
cd "$APP_DIR"
"$NPM" install --omit=dev
echo

if $PRE_CONFIGURED; then
  echo "[3/4] Skipped (pre-configured)."
  echo "[4/4] Skipped (pre-configured)."
else
  echo "[3/4] Requesting Token from server..."
  INSTALL_ID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || "$NODE" -e "console.log(require('crypto').randomUUID())")"

  RESPONSE=$("$NODE" -e "
  const https = require('https');
  const http = require('http');
  const url = new URL('${SERVER_URL}/api/tokens');
  const mod = url.protocol === 'https:' ? https : http;
  const data = JSON.stringify({ platform: '${PLATFORM}', install_id: '${INSTALL_ID}', version: 'portable' });
  const req = mod.request(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(data) } }, (res) => {
    let body = '';
    res.on('data', c => body += c);
    res.on('end', () => {
      if (res.statusCode === 200) { console.log(body); }
      else { console.error('Server error (' + res.statusCode + '): ' + body); process.exit(1); }
    });
  });
  req.on('error', e => { console.error('Network error: ' + e.message); process.exit(1); });
  req.write(data);
  req.end();
  ")

  echo "$RESPONSE" > "$SCRIPT_DIR/token.json"

  TOKEN=$("$NODE" -e "const r=JSON.parse(process.argv[1]);console.log(r.token)" "$RESPONSE")
  CHAT_URL=$("$NODE" -e "const r=JSON.parse(process.argv[1]);console.log(r.chat_url)" "$RESPONSE")
  PROXY_URL=$("$NODE" -e "const r=JSON.parse(process.argv[1]);console.log(r.proxy_base_url)" "$RESPONSE")

  echo "Token: $TOKEN"
  echo "Chat URL: $CHAT_URL"
  echo

  echo "[4/4] Writing configuration..."
  cat > "$APP_DIR/opencat.json" <<EOJSON
{
  "models": {
    "mode": "merge",
    "providers": {
      "proxy": {
        "baseUrl": "$PROXY_URL",
        "apiKey": "$TOKEN",
        "api": "openai-completions",
        "models": [{"id": "auto", "name": "Auto", "reasoning": false, "input": ["text"], "contextWindow": 128000, "maxTokens": 4096}]
      }
    }
  }
}
EOJSON

  cat > "$SCRIPT_DIR/open-chat.html" <<EOHTML
<html><head><meta http-equiv="refresh" content="0;url=$CHAT_URL"></head></html>
EOHTML
  echo "Config written."
fi

echo
echo "=========================================="
echo "  Installation complete!"
echo
if [[ -f "$SCRIPT_DIR/open-chat.html" ]]; then
  echo "  To chat: open open-chat.html"
elif [[ -f "$SCRIPT_DIR/token.json" ]]; then
  echo "  To chat: open the chat_url in token.json"
fi
echo "=========================================="
