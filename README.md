# Tech Tool — Portable AI-Assisted IT Technician Kit

A USB-drive toolkit that gives a technician a local, offline AI assistant plus a vetted
library of diagnostic and repair scripts for **Windows and macOS** — no install, no internet,
runs on modest hardware (8–16 GB RAM, no GPU required).

## What's in here

| Part | What it is |
|------|------------|
| **`TechTool-UI/`** | The app: a zero-dependency Node.js local web server (`server.js`) + single-file UI (`public/index.html`). A clean browser interface with **Guided Tools** (click a tool, run it, get AI analysis) and an **AI Assistant** (chat with the local model, which runs tools for you behind approval gates). |
| **`TechKit/`** | The script library — **67 vetted scripts** (35 PowerShell in `windows/`, 32 bash in `macos/`; ~42 tools), indexed by `catalog.json`. Read-only by default; destructive scripts dry-run first. |
| **`Qwen Coder Tech Agent/`** | The local LLM stack and shared model assets: GGUF weights, llama.cpp builds, and the Qwen Code terminal agent. The UI's `server.js` runs its own `llama-server` from these. (Weights, engine builds, and runtimes are **git-ignored** — see below.) |
| **`Start-Tech-Tool-*.{command,cmd}`** | Double-click launchers for the UI app (macOS / Windows). `Start-Tech-Tool-Granite-*` launch the faster Granite model (see below). |

## Local AI model

Two models ship; the UI runs whichever is selected, fully offline, via its own `llama-server`:

- **Qwen3-4B-Instruct** — the default.
- **IBM Granite 4.0 H-Tiny** — a Mixture-of-Experts model (~1B active params/token) that generates
  roughly **2.5× faster on CPU-only machines**. Start it with the **`Start-Tech-Tool-Granite-*`**
  launchers, or set `TECHTOOL_MODEL=granite`.

There is no cloud call and no web access — the model only reads the diagnostic output it's given,
and only runs tools (or, with approval, shell commands) the technician confirms.

## Key features

- **AI analysis with follow-up** — every diagnostic result has an "Analyze with AI" button that
  summarizes findings (errors highlighted), gives a likely cause, and **prioritized, clickable next
  steps** that jump to the relevant tool. You can then **ask follow-up questions** about the report.
- **Guided tool library** grouped into 6 categories, with time/admin/danger badges shown before you run.
- **Ticket Summary** — auto-generates a ticket-ready session note: a clear auto-generated banner,
  **client-computer details** (OS version, CPU, memory total + in-use, storage used/free, model/serial,
  installed-application list), then the issue / actions / findings / resolution. **Copy** it, **Save to
  USB**, or **Send to TeamDynamix** — which opens the ticket in your already-signed-in browser to paste
  into (no stored credentials).
- **Safety first** — destructive actions dry-run, require confirmation, log to the drive, and
  **never touch administrator accounts**. The large-file cleaner refuses system paths.
- **Native folder picker** — path/destination fields get a "Browse…" button (real OS dialog).
- **New Session** — reset the activity log + assistant conversation to start fresh on the next machine.
- **Clean Exit & Uninstall** — Exit stops the local service; Uninstall removes the AI model + engine
  copied to the client machine (the USB drive is never touched).
- **Save reports** to a `Reports/` folder on the drive.
- **Cross-platform**, fully offline once the drive is built.

## Not in version control

The large binaries that make the kit *work* are intentionally **not committed** (they exceed
GitHub's limits and aren't source): the GGUF model weights, llama.cpp builds, the bundled Node.js
runtime, Qwen Code, and codex binaries — plus runtime logs, collected evidence, and reports.
See [`.gitignore`](.gitignore).

## Building a working drive from a clone

After cloning onto a USB drive, run the bootstrap once to download every platform's binaries
into the ignored folders:

```bash
bash setup.sh            # full kit (downloads several GB: both models, engines, runtimes)
bash setup.sh --no-draft # skip the optional speculative-decoding draft model
```

It fetches assets for **both Windows and macOS** (build on either, run on either), including both
the Qwen and Granite models, and is safe to re-run — existing files are skipped, only missing/failed
ones are retried.

## Running the app

- **Windows:** double-click `Start-Tech-Tool-Windows.cmd` (or `Start-Tech-Tool-Granite-Windows.cmd`)
- **macOS:** double-click `Start-Tech-Tool-Mac.command` (or `Start-Tech-Tool-Granite-Mac.command`)

It extracts the bundled Node runtime, starts a local server on `127.0.0.1:8765`, opens your
browser, and brings up the local AI engine (llama.cpp on `127.0.0.1:8766`). First launch on a new
machine copies the selected model locally (one-time), so subsequent launches are fast.

## Status

Working on Windows and macOS. Built and actively extended through 2026. The macOS scripts and UI
are exercised on real hardware; the Windows scripts are validated for syntax and need a real-PC
run for any newly added tools.
