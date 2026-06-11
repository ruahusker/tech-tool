# Asset Manifest

## Active Model

- `models/qwen3-4b-instruct-2507-q4_k_m.gguf`
  - Source: `https://huggingface.co/lmstudio-community/Qwen3-4B-Instruct-2507-GGUF`
  - Upstream base model: `https://huggingface.co/Qwen/Qwen3-4B-Instruct-2507`
  - Quantization: Q4_K_M
  - Size: 2,497,280,448 bytes

## Experimental Draft Model (speculative decoding, OFF by default)

- `models/qwen3-0.6b-q8_0.gguf`
  - Source: `https://huggingface.co/lmstudio-community/Qwen3-0.6B-GGUF`
  - Quantization: Q8_0
  - Size: 804,753,568 bytes
  - Benchmarked slower than plain decoding for this pairing (0.76x); only used with `QWEN_SPEC=draft`.

## TechKit Script Library

- `../TechKit/` (drive root): 35 technician scripts (19 PowerShell, 16 bash), `catalog.json`,
  per-platform catalog summaries (`catalog-windows.md`, `catalog-macos.md`) injected into the
  agent's QWEN.md by the launchers. Authored on-device 2026-06-11; no external source.

## Qwen Code

- `assets/qwen-code/qwen-code-darwin-arm64.tar.gz`
- `assets/qwen-code/qwen-code-darwin-x64.tar.gz`
- `assets/qwen-code/qwen-code-win-x64.zip`
- Source: `https://github.com/QwenLM/qwen-code/releases/tag/v0.17.1`

## llama.cpp

- `assets/llama.cpp/llama-b9585-bin-macos-arm64.tar.gz`
- `assets/llama.cpp/llama-b9585-bin-macos-x64.tar.gz`
- `assets/llama.cpp/llama-b9585-bin-win-cpu-x64.zip`
- `assets/llama.cpp/llama-b9585-bin-win-vulkan-x64.zip`
- `assets/llama.cpp/llama-b9585-bin-win-cpu-arm64.zip`
