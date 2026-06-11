#!/bin/bash
# Tech Tool - macOS launcher. Double-click to start the app.
# Extracts the bundled Node runtime (one-time) and starts the local UI server,
# which opens your browser to the Tech Tool interface.
set -e

DRIVE_ROOT="$(cd "$(dirname "$0")" && pwd)"
UI_DIR="$DRIVE_ROOT/TechTool-UI"
RUNTIME_DIR="$UI_DIR/runtime"
INSTALL_DIR="$HOME/.tech-utility/qwen-coder-tech-agent"
NODE_HOME="$INSTALL_DIR/node-ui"

ARCH="$(uname -m)"
if [ "$ARCH" = "arm64" ]; then
    NODE_TGZ="$RUNTIME_DIR/node-v22.12.0-darwin-arm64.tar.gz"
    NODE_SUB="node-v22.12.0-darwin-arm64"
else
    NODE_TGZ="$RUNTIME_DIR/node-v22.12.0-darwin-x64.tar.gz"
    NODE_SUB="node-v22.12.0-darwin-x64"
fi

NODE_BIN="$NODE_HOME/$NODE_SUB/bin/node"
if [ ! -x "$NODE_BIN" ]; then
    echo "Setting up Tech Tool (one-time)…"
    mkdir -p "$NODE_HOME"
    tar -xzf "$NODE_TGZ" -C "$NODE_HOME"
    xattr -dr com.apple.quarantine "$NODE_HOME" 2>/dev/null || true
fi

clear
echo "  Tech Tool is starting…"
echo "  Your web browser will open automatically."
echo "  Keep this window open while you work. Close it to quit."
echo ""

exec "$NODE_BIN" "$UI_DIR/server.js"
