#!/bin/zsh
set -euo pipefail

INSTALL_DIR="$HOME/.tech-utility/qwen-coder-tech-agent"
LEGACY_INSTALL_DIR="$HOME/.tech-utility/qwen-coder-codex"
CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CONFIG_TARGET="$CODEX_HOME/qwen-coder.config.toml"
LEGACY_CONFIG_TARGET="$CODEX_HOME/qwen-coder-old.config.toml"
PID_FILE="$INSTALL_DIR/run/llama-server.pid"

printf 'This will uninstall the local Qwen Coder Tech Agent toolkit from this Mac.\n'
printf '\nIt will remove:\n'
printf '  %s\n' "$INSTALL_DIR"
printf '  %s\n' "$LEGACY_INSTALL_DIR"
printf '  %s\n' "$CONFIG_TARGET"
printf '  %s\n' "$LEGACY_CONFIG_TARGET"
printf '\nIt will not remove your normal Qwen Code, Codex, shell, or model settings outside this toolkit.\n'
printf '\nContinue? [y/N] '
read -r answer

case "$answer" in
  y|Y|yes|YES) ;;
  *)
    printf 'Uninstall cancelled.\n'
    exit 0
    ;;
esac

if [[ -f "$PID_FILE" ]]; then
  old_pid="$(cat "$PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" 2>/dev/null || true
  fi
fi

LEGACY_PID_FILE="$LEGACY_INSTALL_DIR/run/llama-server.pid"
if [[ -f "$LEGACY_PID_FILE" ]]; then
  old_pid="$(cat "$LEGACY_PID_FILE" 2>/dev/null || true)"
  if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
    kill "$old_pid" 2>/dev/null || true
  fi
fi

if command -v pgrep >/dev/null 2>&1; then
  pgrep -f "$INSTALL_DIR/llama.cpp/llama-server" 2>/dev/null | while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
  pgrep -f "$LEGACY_INSTALL_DIR/llama.cpp/llama-server" 2>/dev/null | while read -r pid; do
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
  done
fi

rm -rf "$INSTALL_DIR"
rm -rf "$LEGACY_INSTALL_DIR"
rm -f "$CONFIG_TARGET"
rm -f "$LEGACY_CONFIG_TARGET"

printf '\nQwen Coder Tech Agent toolkit uninstalled.\n'
printf 'Press Return to close this window.\n'
read -r _ || true
