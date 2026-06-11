# Tech Tool — Portable AI-Assisted IT Technician Kit

A USB-drive toolkit that gives a technician a local, offline AI assistant plus a vetted
library of diagnostic and repair scripts for **Windows and macOS** — no install, no internet,
runs on modest hardware (8–16 GB RAM, no GPU required).

> Scarlet & cream theme.

## What's in here

| Part | What it is |
|------|------------|
| **`TechTool-UI/`** | The app: a zero-dependency Node.js local web server (`server.js`) + single-file UI (`public/index.html`). Launches a browser interface with **Guided** mode (click a tool, run it, get AI analysis) and **Custom Query** mode (chat with the local model, which runs tools for you with approval gates). |
| **`TechKit/`** | The script library — 35 vetted PowerShell (`windows/`) and bash (`macos/`) diagnostic/repair scripts, indexed by `catalog.json`. Read-only by default; destructive scripts dry-run first. |
| **`Qwen Coder Tech Agent/`** | The local LLM stack: launcher scripts that run a Qwen3-4B model via llama.cpp and Qwen Code. (Model weights, llama.cpp builds, and runtimes are **git-ignored** — see below.) |
| **`Start-Tech-Tool-*.{command,cmd}`** | Double-click launchers for the UI app (macOS / Windows). |

## Key features

- **Local AI analysis** — every diagnostic result has an "Analyze with AI" button that summarizes
  findings (errors highlighted), gives a likely cause, and **prioritized, clickable next steps**
  that jump straight to the relevant tool.
- **Guided tool library** grouped into 6 categories with time/admin/danger badges shown before you run.
- **Safety first** — destructive actions dry-run, require confirmation, log to the drive, and
  **never touch administrator accounts**. The large-file cleaner refuses system paths.
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
bash setup.sh            # full kit (downloads ~3 GB: models, engines, runtimes)
bash setup.sh --no-draft # skip the optional speculative-decoding draft model
```

It fetches assets for **both Windows and macOS** (build on either, run on either) and is safe to
re-run — existing files are skipped, only missing/failed ones are retried.

## Running the app

- **Windows:** double-click `Start-Tech-Tool-Windows.cmd`
- **macOS:** double-click `Start-Tech-Tool-Mac.command`

It extracts the bundled Node runtime, starts a local server on `127.0.0.1:8765`, opens your
browser, and brings up the local AI engine (llama.cpp on `127.0.0.1:8766`).

## Status

Working on Windows and macOS. Built and tested June 2026.
