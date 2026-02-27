#!/usr/bin/env bash
set -euo pipefail

# Build portable zip for a given platform.
# Usage: ./build-portable.sh --platform win-x64 [--node-version 22.22.0] [--openclaw-version latest]

PLATFORM=""
NODE_VERSION="${NODE_VERSION:-22.22.0}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
OUT_DIR="$(pwd)/dist"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --platform) PLATFORM="$2"; shift 2 ;;
    --node-version) NODE_VERSION="$2"; shift 2 ;;
    --openclaw-version) OPENCLAW_VERSION="$2"; shift 2 ;;
    --out-dir) OUT_DIR="$2"; shift 2 ;;
    *) echo "Unknown arg: $1"; exit 1 ;;
  esac
done

if [[ -z "$PLATFORM" ]]; then
  echo "Usage: $0 --platform <win-x64|darwin-arm64|darwin-x64|linux-x64>"
  exit 1
fi

# Map platform to Node download
case "$PLATFORM" in
  win-x64)       NODE_PKG="node-v${NODE_VERSION}-win-x64.zip"; NODE_EXT="zip" ;;
  darwin-arm64)  NODE_PKG="node-v${NODE_VERSION}-darwin-arm64.tar.gz"; NODE_EXT="tar.gz" ;;
  darwin-x64)    NODE_PKG="node-v${NODE_VERSION}-darwin-x64.tar.gz"; NODE_EXT="tar.gz" ;;
  linux-x64)     NODE_PKG="node-v${NODE_VERSION}-linux-x64.tar.gz"; NODE_EXT="tar.gz" ;;
  *) echo "Unsupported platform: $PLATFORM"; exit 1 ;;
esac

NODE_URL="https://nodejs.org/dist/v${NODE_VERSION}/${NODE_PKG}"

BUILD_DIR=$(mktemp -d)
trap "rm -rf $BUILD_DIR" EXIT

BUNDLE_DIR="$BUILD_DIR/openclaw-portable"
mkdir -p "$BUNDLE_DIR/tools" "$BUNDLE_DIR/lib"

echo "==> Downloading Node ${NODE_VERSION} for ${PLATFORM}..."
curl -fsSL "$NODE_URL" -o "$BUILD_DIR/$NODE_PKG"

echo "==> Extracting Node..."
if [[ "$NODE_EXT" == "zip" ]]; then
  unzip -q "$BUILD_DIR/$NODE_PKG" -d "$BUILD_DIR/node-tmp"
  mv "$BUILD_DIR/node-tmp/"node-v*/ "$BUNDLE_DIR/tools/node"
else
  mkdir -p "$BUILD_DIR/node-tmp"
  tar -xzf "$BUILD_DIR/$NODE_PKG" -C "$BUILD_DIR/node-tmp"
  mv "$BUILD_DIR/node-tmp/"node-v*/ "$BUNDLE_DIR/tools/node"
fi

echo "==> Downloading OpenClaw@${OPENCLAW_VERSION}..."
npm pack "openclaw@${OPENCLAW_VERSION}" --pack-destination "$BUILD_DIR" 2>/dev/null || true
OPENCLAW_TGZ=$(ls "$BUILD_DIR"/openclaw-*.tgz 2>/dev/null | head -1)
if [[ -n "$OPENCLAW_TGZ" ]]; then
  mkdir -p "$BUNDLE_DIR/lib/openclaw"
  tar -xzf "$OPENCLAW_TGZ" -C "$BUNDLE_DIR/lib/openclaw" --strip-components=1
else
  echo "WARN: Could not download openclaw package. Place OpenClaw source in lib/openclaw manually."
fi

echo "==> Copying install scripts and templates..."
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ "$PLATFORM" == win-x64 ]]; then
  cp "$SCRIPT_DIR/install.bat" "$BUNDLE_DIR/"
  cp "$SCRIPT_DIR/install.ps1" "$BUNDLE_DIR/" 2>/dev/null || true
  cp "$SCRIPT_DIR/openclaw.bat" "$BUNDLE_DIR/" 2>/dev/null || true
else
  cp "$SCRIPT_DIR/install.sh" "$BUNDLE_DIR/"
  chmod +x "$BUNDLE_DIR/install.sh"
  cp "$SCRIPT_DIR/openclaw.sh" "$BUNDLE_DIR/" 2>/dev/null || true
  chmod +x "$BUNDLE_DIR/openclaw.sh" 2>/dev/null || true
fi

cp "$SCRIPT_DIR/../templates/openclaw.json.template" "$BUNDLE_DIR/lib/openclaw/openclaw.json.template" 2>/dev/null || true
cp "$SCRIPT_DIR/../templates/README.txt" "$BUNDLE_DIR/README.txt" 2>/dev/null || true

echo "==> Creating zip..."
mkdir -p "$OUT_DIR"
ZIP_NAME="openclaw-portable-${PLATFORM}-${OPENCLAW_VERSION}.zip"
(cd "$BUILD_DIR" && zip -qr "$OUT_DIR/$ZIP_NAME" openclaw-portable/)

echo "==> Done: $OUT_DIR/$ZIP_NAME"
