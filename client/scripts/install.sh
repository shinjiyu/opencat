#!/usr/bin/env bash
set -euo pipefail

echo "=========================================="
echo "  OpenClaw Portable - Install"
echo "=========================================="
echo

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
NODE="$SCRIPT_DIR/tools/node/bin/node"
NPM="$SCRIPT_DIR/tools/node/bin/npm"
OPENCLAW_DIR="$SCRIPT_DIR/lib/openclaw"
SERVER_URL="${SERVER_URL:-https://proxy.example.com}"

# Detect platform
ARCH="$(uname -m)"
OS="$(uname -s)"
case "$OS-$ARCH" in
  Darwin-arm64) PLATFORM="darwin-arm64" ;;
  Darwin-x86_64) PLATFORM="darwin-x64" ;;
  Linux-x86_64) PLATFORM="linux-x64" ;;
  *) PLATFORM="unknown" ;;
esac

# Check Node
if [[ ! -x "$NODE" ]]; then
  echo "ERROR: Node not found at $NODE"
  echo "Please re-download the portable package for your platform."
  exit 1
fi

echo "[1/4] Checking Node..."
"$NODE" --version
echo

echo "[2/4] Installing dependencies..."
cd "$OPENCLAW_DIR"
"$NPM" install --omit=dev
echo

echo "[3/4] Requesting Token from server..."
INSTALL_ID="$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || "$NODE" -e "console.log(require('crypto').randomUUID())")"

RESPONSE=$("$NODE" -e "
const https = require('https');
const http = require('http');
const url = new URL('${SERVER_URL}/api/tokens');
const mod = url.protocol === 'https:' ? https : http;
const data = JSON.stringify({ platform: '${PLATFORM}', install_id: '${INSTALL_ID}', version: 'portable' });
const req = mod.request(url, { method: 'POST', headers: { 'Content-Type': 'application/json', 'Content-Length': data.length } }, (res) => {
  let body = '';
  res.on('data', c => body += c);
  res.on('end', () => {
    if (res.statusCode === 200) { console.log(body); }
    else { console.error('Server error: ' + body); process.exit(1); }
  });
});
req.on('error', e => { console.error('Network error: ' + e.message); process.exit(1); });
req.write(data);
req.end();
")

echo "$RESPONSE" > "$SCRIPT_DIR/token.json"

TOKEN=$(echo "$RESPONSE" | "$NODE" -e "process.stdin.on('data',d=>{const r=JSON.parse(d);console.log(r.token)})")
CHAT_URL=$(echo "$RESPONSE" | "$NODE" -e "process.stdin.on('data',d=>{const r=JSON.parse(d);console.log(r.chat_url)})")
PROXY_URL=$(echo "$RESPONSE" | "$NODE" -e "process.stdin.on('data',d=>{const r=JSON.parse(d);console.log(r.proxy_base_url)})")

echo "Token: $TOKEN"
echo "Chat URL: $CHAT_URL"
echo

echo "[4/4] Writing configuration..."
"$NODE" -e "
const fs = require('fs');
const cfg = {
  models: {
    mode: 'merge',
    providers: {
      proxy: {
        baseUrl: '${PROXY_URL}',
        apiKey: '${TOKEN}',
        api: 'openai-completions',
        models: [{ id: 'auto', name: 'Auto', reasoning: false, input: ['text'], contextWindow: 128000, maxTokens: 4096 }]
      }
    }
  }
};
fs.writeFileSync('${OPENCLAW_DIR}/openclaw.json', JSON.stringify(cfg, null, 2));
console.log('Config written.');
"

echo
echo "=========================================="
echo "  Installation complete!"
echo
echo "  Chat URL: $CHAT_URL"
echo "  (Or open token.json to find your chat link)"
echo "=========================================="
