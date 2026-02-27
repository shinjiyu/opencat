#!/usr/bin/env bash
set -euo pipefail

# Build portable zip for a given platform.
# Usage:
#   ./build-portable.sh --platform win-x64 --server-url https://your-server.com
#   ./build-portable.sh --platform all --server-url https://your-server.com
#
# Options:
#   --platform       win-x64 | darwin-arm64 | darwin-x64 | linux-x64 | all
#   --server-url     Proxy server URL (required)
#   --node-version   Node.js version (default: 22.14.0)
#   --app-package    npm package to bundle (default: openclaw@2026.2.26)
#   --out-dir        Output directory (default: ./dist)
#   --pre-token      Pre-allocate a token per package (requires server running)

PLATFORM=""
NODE_VERSION="${NODE_VERSION:-22.14.0}"
APP_PACKAGE="${APP_PACKAGE:-openclaw@2026.2.26}"
OUT_DIR="$(pwd)/dist"
SERVER_URL=""
PRE_TOKEN=false

ALL_PLATFORMS=(win-x64 darwin-arm64 darwin-x64 linux-x64)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) PLATFORM="$2"; shift 2 ;;
    --server-url) SERVER_URL="$2"; shift 2 ;;
    --node-version) NODE_VERSION="$2"; shift 2 ;;
    --app-package) APP_PACKAGE="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --pre-token) PRE_TOKEN=true; shift ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$PLATFORM" ]]; then
  echo "Usage: $0 --platform <win-x64|darwin-arm64|darwin-x64|linux-x64|all> --server-url <url>"
  exit 1
fi
if [[ -z "$SERVER_URL" ]]; then
  echo "ERROR: --server-url is required (e.g. https://your-server.com)"
  exit 1
fi

SERVER_URL="${SERVER_URL%/}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# Extract package name and version for file naming
APP_NAME="${APP_PACKAGE%%@*}"
APP_VERSION="${APP_PACKAGE##*@}"

if [[ "$PLATFORM" == "all" ]]; then
  echo "==> Building all platforms..."
  for p in "${ALL_PLATFORMS[@]}"; do
    echo ""
    echo "========================================"
    echo "  Building: $p"
    echo "========================================"
    EXTRA_ARGS=""
    if $PRE_TOKEN; then EXTRA_ARGS="--pre-token"; fi
    "$0" --platform "$p" --server-url "$SERVER_URL" \
         --node-version "$NODE_VERSION" \
         --app-package "$APP_PACKAGE" \
         --out-dir "$OUT_DIR" $EXTRA_ARGS
  done
  echo ""
  echo "==> All platforms built. Output: $OUT_DIR/"
  ls -lh "$OUT_DIR"/opencat-*.zip 2>/dev/null || true
  exit 0
fi

# --- Single platform build ---

case "$PLATFORM" in
  win-x64)       NODE_PKG="node-v${NODE_VERSION}-win-x64.zip"; NODE_EXT="zip" ;;
  darwin-arm64)  NODE_PKG="node-v${NODE_VERSION}-darwin-arm64.tar.gz"; NODE_EXT="tar.gz" ;;
  darwin-x64)    NODE_PKG="node-v${NODE_VERSION}-darwin-x64.tar.gz"; NODE_EXT="tar.gz" ;;
  linux-x64)     NODE_PKG="node-v${NODE_VERSION}-linux-x64.tar.gz"; NODE_EXT="tar.gz" ;;
  *) echo "Unsupported platform: $PLATFORM"; exit 1 ;;
esac

NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_PKG}"

CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/opencat-build"
mkdir -p "$CACHE_DIR"

BUILD_DIR=$(mktemp -d)
trap 'rm -rf "$BUILD_DIR"' EXIT

BUNDLE_DIR="$BUILD_DIR/opencat-portable"
mkdir -p "$BUNDLE_DIR/tools" "$BUNDLE_DIR/lib"

# --- Step 1: Download & extract Node ---
if [[ -f "$CACHE_DIR/$NODE_PKG" ]]; then
  echo "==> Using cached Node ${NODE_VERSION} for ${PLATFORM}"
  cp "$CACHE_DIR/$NODE_PKG" "$BUILD_DIR/$NODE_PKG"
else
  echo "==> Downloading Node ${NODE_VERSION} for ${PLATFORM}..."
  curl -fSL --progress-bar "$NODE_URL" -o "$BUILD_DIR/$NODE_PKG"
  cp "$BUILD_DIR/$NODE_PKG" "$CACHE_DIR/$NODE_PKG"
fi

echo "==> Extracting Node..."
if [[ "$NODE_EXT" == "zip" ]]; then
  unzip -q "$BUILD_DIR/$NODE_PKG" -d "$BUILD_DIR/node-tmp"
  mv "$BUILD_DIR/node-tmp/"node-v*/ "$BUNDLE_DIR/tools/node"
else
  mkdir -p "$BUILD_DIR/node-tmp"
  tar -xzf "$BUILD_DIR/$NODE_PKG" -C "$BUILD_DIR/node-tmp"
  mv "$BUILD_DIR/node-tmp/"node-v*/ "$BUNDLE_DIR/tools/node"
fi

# --- Step 2: Download application package ---
echo "==> Downloading ${APP_PACKAGE}..."
npm pack "${APP_PACKAGE}" --pack-destination "$BUILD_DIR" 2>/dev/null || true
APP_TGZ=$(ls "$BUILD_DIR"/*.tgz 2>/dev/null | head -1)
if [[ -n "$APP_TGZ" ]]; then
  mkdir -p "$BUNDLE_DIR/lib/app"
  tar -xzf "$APP_TGZ" -C "$BUNDLE_DIR/lib/app" --strip-components=1
else
  echo "WARN: Could not download ${APP_PACKAGE}. Place app source in lib/app manually."
  mkdir -p "$BUNDLE_DIR/lib/app"
fi

# --- Step 3: Inject server URL into install scripts ---
echo "==> Copying install scripts (server: $SERVER_URL)..."

if [[ "$PLATFORM" == win-x64 ]]; then
  sed "s|SERVER_URL=https://proxy.example.com|SERVER_URL=$SERVER_URL|g" \
    "$SCRIPT_DIR/install.bat" > "$BUNDLE_DIR/install.bat"
else
  sed "s|SERVER_URL=\${SERVER_URL:-https://proxy.example.com}|SERVER_URL=\${SERVER_URL:-$SERVER_URL}|g" \
    "$SCRIPT_DIR/install.sh" > "$BUNDLE_DIR/install.sh"
  chmod +x "$BUNDLE_DIR/install.sh"
fi

# --- Step 4: Copy templates ---
cp "$SCRIPT_DIR/../templates/README.txt" "$BUNDLE_DIR/README.txt" 2>/dev/null || true

# --- Step 5 (optional): Pre-allocate token ---
if $PRE_TOKEN; then
  echo "==> Pre-allocating token from $SERVER_URL..."
  INSTALL_ID="$(uuidgen 2>/dev/null || python3 -c 'import uuid; print(uuid.uuid4())' 2>/dev/null || echo "pre-$(date +%s)")"

  TOKEN_RESPONSE=$(curl -sf -X POST "$SERVER_URL/api/tokens" \
    -H 'Content-Type: application/json' \
    -d "{\"platform\":\"$PLATFORM\",\"install_id\":\"$INSTALL_ID\",\"version\":\"$APP_VERSION\"}" \
  ) || {
    echo "WARN: Failed to pre-allocate token. User will need to run install script."
    TOKEN_RESPONSE=""
  }

  if [[ -n "$TOKEN_RESPONSE" ]]; then
    echo "$TOKEN_RESPONSE" > "$BUNDLE_DIR/token.json"

    TOKEN=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])")
    CHAT_URL=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['chat_url'])")
    PROXY_URL=$(echo "$TOKEN_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin)['proxy_base_url'])")

    cat > "$BUNDLE_DIR/lib/app/opencat.json" <<EOJSON
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

    cat > "$BUNDLE_DIR/open-chat.html" <<EOHTML
<html><head><meta http-equiv="refresh" content="0;url=$CHAT_URL"></head></html>
EOHTML

    echo "    Token: $TOKEN"
    echo "    Chat:  $CHAT_URL"
  fi
fi

# --- Step 6: Create zip ---
echo "==> Creating zip..."
mkdir -p "$OUT_DIR"
ZIP_NAME="opencat-portable-${PLATFORM}.zip"
(cd "$BUILD_DIR" && zip -qr "$OUT_DIR/$ZIP_NAME" opencat-portable/)

SIZE=$(du -sh "$OUT_DIR/$ZIP_NAME" | cut -f1)
echo "==> Done: $OUT_DIR/$ZIP_NAME ($SIZE)"
