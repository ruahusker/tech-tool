# Qwen Coder Tech Agent USB Toolkit

This thumb drive installs a local Qwen Code setup from the drive onto a Mac or Windows PC,
wired to the **TechKit script library** (`TechKit/` at the drive root): 35 vetted diagnostic
and repair scripts the model selects, runs, and interprets instead of writing code from scratch.

## Launch

- macOS: double-click `Start-Qwen-Tech-Mac.command`.
- Windows: double-click `Start-Qwen-Tech-Windows.cmd` (CPU-first for PCs without a usable GPU).
- Windows optional Vulkan test: double-click `Start-Qwen-Tech-Windows-Vulkan.cmd`.

The launcher copies Qwen Code, llama.cpp, and the Qwen model from the USB drive to the
computer, starts `llama-server` at `http://127.0.0.1:1234`, writes an isolated workspace whose
`QWEN.md` contains the TechKit catalog (with absolute USB paths), then opens Qwen Code against
the local endpoint with a technician system prompt.

## How the agent works

1. The tech describes the complaint ("it's slow", "no internet", "clean up old accounts").
2. The model matches it to a TechKit script from the catalog in `QWEN.md`, runs it via
   `run_shell_command`, and interprets the output — findings are marked `[!]` in every script.
3. Destructive scripts (user cleanup, temp cleanup) always dry-run first; the model must show
   the dry-run and get explicit confirmation before re-running with the force flag.
   **Administrator accounts can never be disabled or deleted — the scripts refuse, with no
   override flag.**
4. If no script fits, the model writes a custom script to a file (not into chat).
5. Evidence bundles (triage snapshots, log exports, action logs) land in `TechKit/collections/`
   on this drive.

## Performance configuration (measured, not guessed)

- Model: Qwen3-4B Instruct 2507 Q4_K_M, 32K context, 4K max output tokens.
- llama-server runs with flash attention + q8_0 KV cache (halves KV memory at 32K — keeps
  8 GB machines out of swap) and `--cache-reuse 256` (less prompt reprocessing mid-session).
- Windows CPU backend pins threads to physical core count (hyperthreads hurt GEMM).
- On Apple Silicon, full Metal GPU offload (~80 tok/s on an M-series Pro).
- Speculative decoding (draft model and ngram variants) was benchmarked **slower** than plain
  decoding for this model pairing and is OFF by default. `models/qwen3-0.6b-q8_0.gguf` stays
  on the drive for experiments: launch with `QWEN_SPEC=draft` (or an ngram type) to test.

## Environment overrides (one run, from a terminal)

- `QWEN_SYSTEM_PROMPT="..."` - replace the technician prompt
- `QWEN_APPROVAL_MODE=yolo` - auto-approve all tool calls (default `auto-edit`: edits free, shell asks)
- `QWEN_CONTEXT_SIZE` / `QWEN_MAX_OUTPUT_TOKENS` - context/output limits (default 32768 / 4096)
- `QWEN_SPEC=off|draft|ngram-simple|...` - speculative decoding mode (default off)
- `QWEN_LLAMA_BACKEND=cpu|vulkan|auto` - Windows llama.cpp backend (default cpu)

## Uninstall

- macOS: double-click `Uninstall-Qwen-Tech-Mac.command`.
- Windows: double-click `Uninstall-Qwen-Tech-Windows.cmd`.

Removes only this toolkit's install directory (`~/.tech-utility/qwen-coder-tech-agent`);
nothing else on the machine is touched. TechKit scripts run from the USB and install nothing.

## Logs

Each run writes launcher + llama-server + OpenAI request/response logs to `logs/` on this
drive (copied at server start and again on exit, so they survive a yanked drive).
