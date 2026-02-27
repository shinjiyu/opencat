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
#   --pre-token      Pre-allocate a token per package (default: on, requires server running)
#   --no-pre-token   Disable pre-allocate token
#   --build-secret   Secret for POST /api/tokens (env BUILD_SECRET or this arg; required when server sets BUILD_SECRET)

PLATFORM=""
NODE_VERSION="${NODE_VERSION:-22.14.0}"
APP_PACKAGE="${APP_PACKAGE:-openclaw@2026.2.26}"
OUT_DIR="$(pwd)/dist"
SERVER_URL="${SERVER_URL:-https://kuroneko.chat/opencat}"
PRE_TOKEN=true
BUILD_SECRET="${BUILD_SECRET:-}"

ALL_PLATFORMS=(win-x64 darwin-arm64 darwin-x64 linux-x64)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) PLATFORM="$2"; shift 2 ;;
    --server-url) SERVER_URL="$2"; shift 2 ;;
    --node-version) NODE_VERSION="$2"; shift 2 ;;
    --app-package) APP_PACKAGE="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    --pre-token) PRE_TOKEN=true; shift ;;
    --no-pre-token) PRE_TOKEN=false; shift ;;
    --build-secret) BUILD_SECRET="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$PLATFORM" ]]; then
  echo "Usage: $0 --platform <win-x64|darwin-arm64|darwin-x64|linux-x64|all> --server-url <url>"
  exit 1
fi
if [[ -z "$SERVER_URL" ]]; then
  echo "ERROR: --server-url is required (e.g. https://kuroneko.chat/opencat)"
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
    [[ -n "$BUILD_SECRET" ]] && EXTRA_ARGS="$EXTRA_ARGS --build-secret $BUILD_SECRET"
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

# --- Step 2a: Patch gateway to skip device identity check ---
for f in "$BUNDLE_DIR"/lib/app/dist/gateway-cli-*.js; do
  if [[ -f "$f" ]]; then
    sed -i 's/function evaluateMissingDeviceIdentity(params) {/function evaluateMissingDeviceIdentity(params) { return { kind: "allow" };/' "$f"
  fi
done
echo "    Gateway patched (device identity bypass)"

# --- Step 2b: Download cloudflared ---
echo "==> Downloading cloudflared for ${PLATFORM}..."
case "$PLATFORM" in
  win-x64)       CF_FILE="cloudflared-windows-amd64.exe"; CF_BIN="cloudflared.exe" ;;
  darwin-arm64)  CF_FILE="cloudflared-darwin-arm64.tgz"; CF_BIN="cloudflared" ;;
  darwin-x64)    CF_FILE="cloudflared-darwin-amd64.tgz"; CF_BIN="cloudflared" ;;
  linux-x64)     CF_FILE="cloudflared-linux-amd64"; CF_BIN="cloudflared" ;;
esac
CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/${CF_FILE}"

mkdir -p "$BUNDLE_DIR/tools/cloudflared"
if [[ -f "$CACHE_DIR/$CF_FILE" ]]; then
  echo "    Using cached cloudflared"
  cp "$CACHE_DIR/$CF_FILE" "$BUILD_DIR/$CF_FILE"
else
  curl -fSL --progress-bar "$CF_URL" -o "$BUILD_DIR/$CF_FILE" || {
    echo "WARN: Failed to download cloudflared. Tunnel will not be bundled."
    CF_FILE=""
  }
  [[ -n "$CF_FILE" ]] && cp "$BUILD_DIR/$CF_FILE" "$CACHE_DIR/$CF_FILE"
fi

if [[ -n "$CF_FILE" ]]; then
  if [[ "$CF_FILE" == *.tgz ]]; then
    tar -xzf "$BUILD_DIR/$CF_FILE" -C "$BUNDLE_DIR/tools/cloudflared"
  else
    cp "$BUILD_DIR/$CF_FILE" "$BUNDLE_DIR/tools/cloudflared/$CF_BIN"
  fi
  chmod +x "$BUNDLE_DIR/tools/cloudflared/$CF_BIN" 2>/dev/null || true
  echo "    cloudflared bundled at tools/cloudflared/$CF_BIN"
fi

# --- Step 3: Copy install + startup scripts ---
echo "==> Copying scripts (server: $SERVER_URL)..."

cp "$SCRIPT_DIR/configure-gateway.js" "$BUNDLE_DIR/configure-gateway.js"
if [[ "$PLATFORM" == win-x64 ]]; then
  for f in install.bat startup.bat shutdown.bat; do
    cp "$SCRIPT_DIR/$f" "$BUNDLE_DIR/$f"
    sed 's/$/\r/' "$BUNDLE_DIR/$f" > "$BUNDLE_DIR/$f.crlf" && mv "$BUNDLE_DIR/$f.crlf" "$BUNDLE_DIR/$f"
  done
else
  cp "$SCRIPT_DIR/install.sh" "$BUNDLE_DIR/install.sh"
  cp "$SCRIPT_DIR/startup.sh" "$BUNDLE_DIR/startup.sh"
  cp "$SCRIPT_DIR/shutdown.sh" "$BUNDLE_DIR/shutdown.sh"
  chmod +x "$BUNDLE_DIR/install.sh" "$BUNDLE_DIR/startup.sh" "$BUNDLE_DIR/shutdown.sh"
fi

# --- Step 4: Copy templates ---
cp "$SCRIPT_DIR/../templates/README.txt" "$BUNDLE_DIR/README.txt" 2>/dev/null || true
rm -f "$BUNDLE_DIR/open-chat.html" 2>/dev/null || true

# --- Step 5 (optional): Pre-allocate token ---
if $PRE_TOKEN; then
  echo "==> Pre-allocating token from $SERVER_URL..."
  BUILD_NODE="$BUNDLE_DIR/tools/node/node.exe"
  [[ -x "$BUILD_NODE" ]] || BUILD_NODE="$BUNDLE_DIR/tools/node/bin/node"
  INSTALL_ID="$(uuidgen 2>/dev/null || "$BUILD_NODE" -e "console.log(require('crypto').randomUUID())" 2>/dev/null || echo "pre-$(date +%s)")"

  TOKEN_RESPONSE=$(curl -sf -X POST "$SERVER_URL/api/tokens" \
    -H 'Content-Type: application/json' \
    -H "X-Build-Secret: ${BUILD_SECRET}" \
    -d "{\"platform\":\"$PLATFORM\",\"install_id\":\"$INSTALL_ID\",\"version\":\"$APP_VERSION\"}" \
  ) || {
    echo "WARN: Failed to pre-allocate token. User will need to run install script."
    TOKEN_RESPONSE=""
  }

  if [[ -n "$TOKEN_RESPONSE" ]]; then
    echo "$TOKEN_RESPONSE" > "$BUNDLE_DIR/token.json"

    TOKEN=$("$BUILD_NODE" -e "const r=JSON.parse(process.argv[1]); console.log(r.token)" "$TOKEN_RESPONSE")
    PROXY_URL=$("$BUILD_NODE" -e "const r=JSON.parse(process.argv[1]); console.log(r.proxy_base_url)" "$TOKEN_RESPONSE")

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

    # Create shortcut files (openclaw redirect = Kuroneko entry; no chat UI)
    OPENCLAW_URL="$SERVER_URL/openclaw?token=$TOKEN"
    LOCAL_URL="http://localhost:3080"

    if [[ "$PLATFORM" == win-x64 ]]; then
      printf '[InternetShortcut]\r\nURL=%s\r\n' "$OPENCLAW_URL" > "$BUNDLE_DIR/Kuroneko.url"
      printf '[InternetShortcut]\r\nURL=%s\r\n' "$LOCAL_URL"    > "$BUNDLE_DIR/OpenClaw Local.url"
    else
      cat > "$BUNDLE_DIR/open-kuroneko.html" <<EOHTML
<html><head><meta http-equiv="refresh" content="0;url=$OPENCLAW_URL"></head></html>
EOHTML
      cat > "$BUNDLE_DIR/open-local.html" <<EOHTML
<html><head><meta http-equiv="refresh" content="0;url=$LOCAL_URL"></head></html>
EOHTML
    fi

    echo "    Token: $TOKEN"
    echo "    Proxy: $PROXY_URL"
  fi
fi

# --- Step 6: Create zip (standard .zip format, no 7z) ---
echo "==> Creating zip..."
mkdir -p "$OUT_DIR"
if [[ -n "${TOKEN:-}" ]]; then
  ZIP_NAME="opencat-portable-${PLATFORM}-${TOKEN}.zip"
else
  ZIP_NAME="opencat-portable-${PLATFORM}.zip"
fi

# Prefer zip from repo tools/ (bundled); then system zip
BUNDLED_ZIP="$SCRIPT_DIR/tools/zip.exe"
ZIP_CMD=""
if [[ "$PLATFORM" == "win-x64" ]] && [[ -x "$BUNDLED_ZIP" || -f "$BUNDLED_ZIP" ]]; then
  ZIP_CMD="$BUNDLED_ZIP"
elif command -v zip &>/dev/null; then
  ZIP_CMD="zip"
fi

if [[ -z "$ZIP_CMD" ]]; then
  echo "ERROR: zip not found. For win-x64 build, ensure client/scripts/tools/zip.exe exists (Info-ZIP). For other platforms, install zip (e.g. 'apt install zip' or 'brew install zip')."
  exit 1
fi

# Create zip: recursive, quiet. On Windows zip.exe we need Windows paths for output
if [[ "$ZIP_CMD" == *.exe ]]; then
  # Convert Unix path to Windows path for zip.exe (e.g. /c/opencat/... -> C:\opencat\...)
  WIN_OUT=$(echo "$OUT_DIR" | sed 's|^/\([a-zA-Z]\)/|\1:/|' | sed 's|/|\\|g')
  WIN_ZIP_PATH="$WIN_OUT\\$ZIP_NAME"
  (cd "$BUILD_DIR" && "$ZIP_CMD" -r -q "$WIN_ZIP_PATH" opencat-portable/)
else
  (cd "$BUILD_DIR" && "$ZIP_CMD" -r -q "$OUT_DIR/$ZIP_NAME" opencat-portable/)
fi

SIZE=$(du -sh "$OUT_DIR/$ZIP_NAME" 2>/dev/null | cut -f1 || echo "N/A")
echo "==> Done: $OUT_DIR/$ZIP_NAME ($SIZE)"
