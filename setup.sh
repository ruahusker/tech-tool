#!/bin/bash
# Tech Tool — asset bootstrap.
# A fresh git clone contains only source; this downloads the large binaries that are
# git-ignored (AI models, llama.cpp engine builds, Node.js runtime, Qwen Code) and places
# them so the kit runs. Fetches assets for ALL platforms so the resulting drive works on
# both Windows and macOS, regardless of which machine you build it on.
#
# Safe to re-run: existing, non-empty files are skipped.
# Usage:  bash setup.sh            (full kit)
#         bash setup.sh --no-draft (skip the optional speculative-decoding draft model)
set -u

ROOT="$(cd "$(dirname "$0")" && pwd)"
AGENT="$ROOT/Qwen Coder Tech Agent"
WANT_DRAFT=1
[ "${1:-}" = "--no-draft" ] && WANT_DRAFT=0

LLAMA_BUILD="b9585"
NODE_VER="v22.12.0"
QWEN_CODE_VER="v0.17.1"

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required."; exit 1; }

total=0; got=0; skipped=0; failed=0
# fetch <url> <destination-file>
fetch() {
  local url="$1" dest="$2"
  total=$((total+1))
  mkdir -p "$(dirname "$dest")"
  if [ -s "$dest" ]; then
    echo "  skip   $(basename "$dest")  (already present)"
    skipped=$((skipped+1)); return 0
  fi
  echo "  get    $(basename "$dest") ..."
  if curl -fL --retry 3 --retry-delay 2 -# -o "$dest.part" "$url"; then
    mv "$dest.part" "$dest"; got=$((got+1))
  else
    rm -f "$dest.part"; echo "  [!] FAILED: $url"; failed=$((failed+1))
  fi
}

echo "Tech Tool setup — downloading platform assets into git-ignored folders."
echo "Root: $ROOT"
echo ""

echo "== AI models =="
fetch "https://huggingface.co/lmstudio-community/Qwen3-4B-Instruct-2507-GGUF/resolve/main/Qwen3-4B-Instruct-2507-Q4_K_M.gguf" \
      "$AGENT/models/qwen3-4b-instruct-2507-q4_k_m.gguf"
# Granite 4.0 H-Tiny — faster MoE alternative for slow CPU machines (TECHTOOL_MODEL=granite).
fetch "https://huggingface.co/bartowski/ibm-granite_granite-4.0-h-tiny-GGUF/resolve/main/ibm-granite_granite-4.0-h-tiny-Q4_K_M.gguf" \
      "$AGENT/models/granite-4.0-h-tiny-q4_k_m.gguf"
if [ "$WANT_DRAFT" = "1" ]; then
  fetch "https://huggingface.co/lmstudio-community/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf" \
        "$AGENT/models/qwen3-0.6b-q8_0.gguf"
fi

echo ""
echo "== llama.cpp engine ($LLAMA_BUILD) =="
LB="https://github.com/ggml-org/llama.cpp/releases/download/$LLAMA_BUILD"
for f in macos-arm64.tar.gz macos-x64.tar.gz win-cpu-x64.zip win-vulkan-x64.zip win-cpu-arm64.zip; do
  fetch "$LB/llama-$LLAMA_BUILD-bin-$f" "$AGENT/assets/llama.cpp/llama-$LLAMA_BUILD-bin-$f"
done

echo ""
echo "== Node.js runtime ($NODE_VER) for the UI =="
NB="https://nodejs.org/dist/$NODE_VER"
fetch "$NB/node-$NODE_VER-win-x64.zip"        "$ROOT/TechTool-UI/runtime/node-$NODE_VER-win-x64.zip"
fetch "$NB/node-$NODE_VER-darwin-arm64.tar.gz" "$ROOT/TechTool-UI/runtime/node-$NODE_VER-darwin-arm64.tar.gz"
fetch "$NB/node-$NODE_VER-darwin-x64.tar.gz"   "$ROOT/TechTool-UI/runtime/node-$NODE_VER-darwin-x64.tar.gz"

echo ""
echo "== Qwen Code ($QWEN_CODE_VER) for the terminal agent =="
QC="https://github.com/QwenLM/qwen-code/releases/download/$QWEN_CODE_VER"
for f in darwin-arm64.tar.gz darwin-x64.tar.gz win-x64.zip; do
  fetch "$QC/qwen-code-$f" "$AGENT/assets/qwen-code/qwen-code-$f"
done

echo ""
echo "=================================================="
echo "Done. $got downloaded, $skipped already present, $failed failed (of $total)."
if [ "$failed" -gt 0 ]; then
  echo "[!] Some downloads failed — re-run 'bash setup.sh' to retry just the missing ones."
  exit 1
fi
echo "The drive is ready. Launch with Start-Tech-Tool-Mac.command / Start-Tech-Tool-Windows.cmd."
