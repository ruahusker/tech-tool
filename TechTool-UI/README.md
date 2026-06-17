# Tech Tool UI

The graphical front-end for the USB technician toolkit. Double-click one launcher and a
real app opens in your browser — no command line, no remembering script names.

## Launch

- **Windows:** double-click `Start-Tech-Tool-Windows.cmd` (at the drive root)
- **macOS:** double-click `Start-Tech-Tool-Mac.command` (at the drive root)
- **Faster on CPU-only machines:** use the `Start-Tech-Tool-Granite-*` launchers to run the
  IBM Granite 4.0 H-Tiny model instead of the default Qwen3-4B (see *Model selection* below).

First launch extracts a bundled Node.js runtime and (if not already present) copies the AI
model to the computer — a one-time setup of a minute or two, shown on a progress screen.
After that it opens `http://127.0.0.1:8765` in the default browser. Keep the small console
window open while you work; closing it (or the in-app **Exit** button) quits the app and stops
the local AI engine.

## Two modes

**Guided Tools** — a menu of tools grouped by area (Overview, Performance, Network, Storage,
Logs & Repair, Security & Users). Click a card, optionally set a couple of options (path fields
get a **Browse…** folder picker), and Run. Scripts that change the system are badged
"changes system" and run in **Preview (dry-run) first**; an "Apply changes" button appears only
after you've seen the preview.

**AI Assistant** — describe the problem in plain words. The local AI picks the right TechKit
script, runs it, and explains the findings (leading with `[!]` items). It asks for explicit
approval before any raw shell command or any system-changing flag. Denying is respected — it
won't retry, it suggests a safer route.

## Analysis, follow-ups & tickets

- **Analyze with AI** on any result → a structured summary (findings, likely cause, numbered
  next steps that link straight to the relevant tool). You can then **ask follow-up questions**
  about that report in a small chat thread.
- **Ticket Summary** (top bar) → an auto-generated, ticket-ready note: a banner marking it
  auto-generated, a **Client Computer** block (OS version, CPU, memory total + in-use, storage
  used/free, model/serial, installed applications), then issue / actions / findings / resolution.
  **Copy**, **Save to USB**, or **Send to TeamDynamix** (opens the ticket in your already-signed-in
  browser to paste into — no credentials are stored).
- **New Session** (top bar) → clears the activity log + assistant conversation to start fresh on
  the next computer. Saved reports are kept.
- **Uninstall** (sidebar) → removes the AI model + engine copied to *this* machine
  (`~/.tech-utility/qwen-coder-tech-agent`); the USB drive is never touched.

## Safety model

- Read-only scripts run immediately. System-changing actions always require a click.
- Destructive scripts dry-run first in both modes.
- **Administrator accounts can never be removed** — enforced in the scripts themselves.
- The server binds to `127.0.0.1` only; nothing is exposed to the network, and the model has no
  web access (it only interprets the output it's given).

## Model selection

`TECHTOOL_MODEL` chooses the local model (default `qwen`):

- `qwen` — Qwen3-4B-Instruct (default).
- `granite` — IBM Granite 4.0 H-Tiny; a Mixture-of-Experts model (~1B active params/token) that
  generates ~2.5× faster on CPU-only machines. Carries its own tool-calling chat template in the
  GGUF (runs with `--jinja`, no external template file). The `Start-Tech-Tool-Granite-*` launchers
  just set `TECHTOOL_MODEL=granite` and hand off to the standard launcher.

## Architecture (for maintainers)

- `server.js` — zero-dependency Node backend: owns setup, the `llama-server` lifecycle, the model
  registry (`MODELS` / `TECHTOOL_MODEL`), the guided `/api/run` endpoint, and the assistant tool-loop
  (`/api/chat`, `/api/confirm`). Other endpoints: `/api/analyze`, `/api/followup`, `/api/ticket`,
  `/api/savereport`, `/api/largefiles`, `/api/deletefiles`, `/api/pickfolder`, `/api/reset`,
  `/api/exit`, `/api/uninstall`. Reuses `~/.tech-utility/qwen-coder-tech-agent` so it shares the
  model copy with the Qwen Code launchers. Speed flags match those launchers (flash attention,
  q8_0 KV cache, cache-reuse, physical-core threads on Windows).
- `getMachineInfo()` / `getInstalledApps()` gather the Client Computer block for the ticket
  (`sw_vers`/CIM for OS version, `vm_stat`/CIM for memory-in-use, `df`/CIM for storage, app list).
- `pickFolder()` runs the native OS folder dialog (`osascript` / `FolderBrowserDialog`) for the
  Browse buttons — browsers can't return a real absolute path.
- `public/index.html` — single-file UI (no build step, no framework); inline SVG icon set.
- `runtime/` — bundled Node.js for win-x64, darwin-arm64, darwin-x64.
- Script metadata comes from `../TechKit/catalog.json`; the assistant's system prompt embeds
  `../TechKit/catalog-<platform>.md`. `scriptById()` accepts catalog ids OR bare filenames,
  since the local model tends to call scripts by filename.

## Environment overrides

`TECHTOOL_MODEL=qwen|granite`, `QWEN_CONTEXT_SIZE`, `QWEN_MAX_OUTPUT_TOKENS`,
`QWEN_LLAMA_BACKEND=cpu|vulkan` (Windows), `TECHTOOL_LLAMA_PORT`. Set `TECHTOOL_NO_BROWSER=1`
to start the server without auto-opening a browser (useful for testing).
