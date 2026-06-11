# Tech Tool UI

The graphical front-end for the USB technician toolkit. Double-click one launcher and a
real app opens in your browser — no command line, no remembering script names.

## Launch

- **Windows:** double-click `Start-Tech-Tool-Windows.cmd` (at the drive root)
- **macOS:** double-click `Start-Tech-Tool-Mac.command` (at the drive root)

First launch extracts a bundled Node.js runtime and (if not already present) copies the AI
model to the computer — a one-time setup of a minute or two, shown on a progress screen.
After that it opens `http://127.0.0.1:8765` in the default browser. Keep the small console
window open while you work; closing it quits the app and stops the local AI engine.

## Two modes

**Guided** — a menu of tools grouped by problem (Speed, Network, Disk, Security, Accounts…).
Click a card, optionally set a couple of options, and Run. Scripts that change the system are
badged "changes system" and run in **Preview (dry-run) first**; an "Apply changes" button
appears only after you've seen the preview.

**Ask the Assistant** — describe the problem in plain words. The local AI picks the right
TechKit script, runs it, and explains the findings (leading with `[!]` items). It asks for
explicit approval before any raw shell command or any system-changing flag. Denying is
respected — it won't retry, it suggests a safer route.

## Safety model

- Read-only scripts run immediately. System-changing actions always require a click.
- Destructive scripts dry-run first in both modes.
- **Administrator accounts can never be removed** — enforced in the scripts themselves.
- The server binds to `127.0.0.1` only; nothing is exposed to the network.

## Architecture (for maintainers)

- `server.js` — zero-dependency Node backend: owns setup, the llama-server lifecycle, the
  guided `/api/run` endpoint, and the assistant tool-loop (`/api/chat`, `/api/confirm`).
  Reuses `~/.tech-utility/qwen-coder-tech-agent` so it shares the model copy with the Qwen
  Code launchers. Speed flags match those launchers (flash attention, q8_0 KV cache,
  cache-reuse, physical-core threads on Windows).
- `public/index.html` — single-file UI (no build step, no framework).
- `runtime/` — bundled Node.js 22.12.0 for win-x64, darwin-arm64, darwin-x64.
- Script metadata comes from `../TechKit/catalog.json`; the assistant's system prompt embeds
  `../TechKit/catalog-<platform>.md`. `scriptById()` accepts catalog ids OR bare filenames,
  since the local model tends to call scripts by filename.

## Environment overrides

Same as the Qwen Code launchers: `QWEN_CONTEXT_SIZE`, `QWEN_MAX_OUTPUT_TOKENS`,
`QWEN_LLAMA_BACKEND=cpu|vulkan` (Windows). Set `TECHTOOL_NO_BROWSER=1` to start the server
without auto-opening a browser (useful for testing).
