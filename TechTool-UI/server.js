#!/usr/bin/env node
/*
 * Tech Tool UI - local backend for the USB technician toolkit.
 * Zero npm dependencies; runs on the Node runtime bundled on the drive.
 *
 * Responsibilities:
 *  - one-time setup on this machine (copy model, extract llama.cpp) into
 *    ~/.tech-utility/qwen-coder-tech-agent (shared with the Qwen Code launchers)
 *  - start/own llama-server with the benchmarked speed flags
 *  - serve the web UI on http://127.0.0.1:8765 (loopback only)
 *  - guided mode: run TechKit scripts directly
 *  - assistant mode: chat with the local model; the model can call TechKit
 *    scripts / shell commands through a tool loop with user approval gates
 */
"use strict";

const http = require("http");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { spawn, spawnSync } = require("child_process");
const crypto = require("crypto");

// ---------- paths ----------
const UI_DIR = __dirname;
const DRIVE_ROOT = path.dirname(UI_DIR);
const AGENT_DIR = path.join(DRIVE_ROOT, "Qwen Coder Tech Agent");
const TECHKIT_DIR = path.join(DRIVE_ROOT, "TechKit");
const INSTALL_DIR = path.join(os.homedir(), ".tech-utility", "qwen-coder-tech-agent");
// Model registry — choose with TECHTOOL_MODEL (default: qwen). Granite 4.0 H-Tiny is a
// Mixture-of-Experts model (7B total, ~1B active per token), aimed at slow CPU-only
// machines: it reads far fewer params per token so it generates noticeably faster, and
// its hybrid-Mamba layers keep the KV cache small. It carries its own tool-calling chat
// template inside the GGUF, so it uses --jinja with no external template file.
const MODELS = {
  qwen: { file: "qwen3-4b-instruct-2507-q4_k_m.gguf", template: "Qwen3-4B-Instruct-2507.jinja", label: "AI model (2.5 GB)" },
  granite: { file: "granite-4.0-h-tiny-q4_k_m.gguf", template: null, label: "AI model (4 GB)" },
};
const MODEL_KEY = (process.env.TECHTOOL_MODEL || "qwen").toLowerCase();
const MODEL = MODELS[MODEL_KEY] || MODELS.qwen;
const MODEL_FILE = MODEL.file;
const TEMPLATE_FILE = MODEL.template;
const IS_WIN = process.platform === "win32";
const PLATFORM = IS_WIN ? "windows" : "macos";
const UI_PORT = 8765;
// Our own llama-server lives on a private port, NOT the common 1234 - that one is
// frequently taken by LM Studio / Ollama / the Qwen Code launcher, and we must not
// hijack a different tool's model. Override with TECHTOOL_LLAMA_PORT if needed.
const LLAMA_PORT = parseInt(process.env.TECHTOOL_LLAMA_PORT || "8766", 10);
const LLAMA_URL = `http://127.0.0.1:${LLAMA_PORT}`;
const EXPECTED_MODEL_ID = "local/" + MODEL_FILE.replace(/\.gguf$/, "");

// ---------- state ----------
const status = { step: "starting", detail: "", ready: false, error: null, modelId: null };
const sessions = new Map(); // sessionId -> { messages: [], pending: null }
let catalog = null;

// Session activity log — feeds the "Ticket Summary" feature.
const activity = [];
function logActivity(entry) {
  activity.push({ t: new Date().toISOString(), ...entry });
  if (activity.length > 200) activity.shift();
}
// Keep the signal from a tool's output: flagged [!] lines + a short head, trimmed.
function digestOutput(output) {
  const text = String(output || "");
  const lines = text.split("\n");
  const flagged = lines.filter((l) => l.includes("[!]")).slice(0, 12);
  const head = lines.filter((l) => l.trim()).slice(0, 4);
  let d = (flagged.length ? "Flags:\n" + flagged.join("\n") + "\n" : "") + head.join("\n");
  if (d.length > 1000) d = d.slice(0, 1000) + " …";
  return d.trim();
}
let llamaProc = null;

function log(msg) {
  console.log(`[${new Date().toISOString().slice(11, 19)}] ${msg}`);
}

// ---------- catalog ----------
function loadCatalog() {
  const raw = JSON.parse(fs.readFileSync(path.join(TECHKIT_DIR, "catalog.json"), "utf8"));
  catalog = raw.scripts.filter((s) => s.platform === PLATFORM);
}

function scriptById(id) {
  if (!id) return undefined;
  const want = String(id).toLowerCase();
  // Match on: exact catalog id, the script filename, the filename without
  // extension, or the id without its platform prefix. The local model tends to
  // call scripts by filename, so accepting these avoids a wasted retry cycle.
  return catalog.find((s) => {
    const file = s.path.split("/").pop().toLowerCase();
    return (
      s.id === want ||
      file === want ||
      file.replace(/\.(ps1|sh)$/, "") === want ||
      s.id.replace(/^(win|mac)-/, "") === want.replace(/^(win|mac)-/, "")
    );
  });
}

function scriptAbsPath(entry) {
  return path.join(TECHKIT_DIR, entry.path.split("/").join(path.sep));
}

// Args that flip a script from diagnose to act - these require explicit approval.
const FORCE_PATTERN = /(^|\s)(-force|--force|-repair|-clearqueue|-restartspooler|-delete|--delete|--remove-home|-removeprofile|--trash|-includerecyclebin|-includewindowsupdate|--verify)?$/i;
function argsNeedConfirm(args) {
  const joined = (args || []).join(" ").toLowerCase();
  return /(-force|--force|-repair\b|-clearqueue|-restartspooler|--delete|-delete\b|--remove-home|-removeprofile|--trash|-includerecyclebin|-includewindowsupdate)/.test(joined);
}

// ---------- setup (model copy + llama.cpp extraction + server start) ----------
async function fetchJson(url, opts) {
  return new Promise((resolve, reject) => {
    const req = http.request(url, opts || {}, (res) => {
      let body = "";
      res.on("data", (c) => (body += c));
      res.on("end", () => {
        try { resolve({ status: res.statusCode, json: JSON.parse(body || "{}") }); }
        catch (e) { resolve({ status: res.statusCode, json: null, raw: body }); }
      });
    });
    req.on("error", reject);
    if (opts && opts.body) req.write(opts.body);
    req.end();
  });
}

async function llamaAlive() {
  try {
    const r = await fetchJson(`${LLAMA_URL}/v1/models`);
    if (r.status === 200 && r.json && r.json.data && r.json.data.length) {
      // Only treat it as "ours" if it is actually serving our model. This guards
      // against reusing a foreign server (e.g. LM Studio) that happens to share a port.
      const ids = r.json.data.map((m) => m.id);
      if (ids.includes(EXPECTED_MODEL_ID)) { status.modelId = EXPECTED_MODEL_ID; return true; }
      return false;
    }
  } catch (_) {}
  return false;
}

function copyIfNeeded(src, dst, label) {
  if (!fs.existsSync(src)) throw new Error(`Missing on USB: ${src}`);
  const need = !fs.existsSync(dst) || fs.statSync(src).size !== fs.statSync(dst).size;
  if (need) {
    status.detail = `Copying ${label} to this computer (one-time)...`;
    log(status.detail);
    fs.mkdirSync(path.dirname(dst), { recursive: true });
    fs.copyFileSync(src, dst);
  }
}

function findAsset(dir, regex) {
  const hit = fs.readdirSync(dir).find((f) => regex.test(f));
  return hit ? path.join(dir, hit) : null;
}

// Recursively total the byte size of a directory (used to report freed space on uninstall).
function dirSize(dir) {
  let total = 0;
  const walk = (d) => {
    let entries;
    try { entries = fs.readdirSync(d, { withFileTypes: true }); } catch (_) { return; }
    for (const e of entries) {
      const p = path.join(d, e.name);
      try {
        if (e.isDirectory()) walk(p);
        else { const st = fs.lstatSync(p); if (st.isFile()) total += st.size; }
      } catch (_) {}
    }
  };
  walk(dir);
  return total;
}

function findServerBinary(root) {
  // Depth-first search for the server binary; the archive nests it in a
  // versioned subfolder (e.g. llama-b9585/).
  const serverName = IS_WIN ? "llama-server.exe" : "llama-server";
  let found = null;
  const walk = (d) => {
    if (found) return;
    for (const f of fs.readdirSync(d)) {
      const p = path.join(d, f);
      let st;
      try { st = fs.lstatSync(p); } catch (_) { continue; }
      if (st.isDirectory()) walk(p);
      else if (f === serverName) { found = p; return; }
    }
  };
  if (fs.existsSync(root)) walk(root);
  return found;
}

function extractLlama() {
  const dest = path.join(INSTALL_DIR, "llama.cpp");
  // Fast path: already extracted and runnable.
  const existing = findServerBinary(dest);
  if (existing) return existing;

  status.detail = "Extracting llama.cpp engine (one-time)...";
  log(status.detail);
  const assetDir = path.join(AGENT_DIR, "assets", "llama.cpp");
  let archive;
  if (IS_WIN) {
    const backend = (process.env.QWEN_LLAMA_BACKEND || "cpu").toLowerCase();
    archive = findAsset(assetDir, backend === "vulkan" ? /bin-win-vulkan-x64\.zip$/ : /bin-win-cpu-x64\.zip$/);
  } else {
    archive = findAsset(assetDir, process.arch === "arm64" ? /bin-macos-arm64\.tar\.gz$/ : /bin-macos-x64\.tar\.gz$/);
  }
  if (!archive) throw new Error("No llama.cpp archive for this platform on the USB drive");

  // Extract directly into the final location. Extracting in place keeps the
  // relative dylib symlinks valid; the previous extract-to-temp-then-copy
  // approach left them pointing into a temp dir that was then deleted, so
  // llama-server could not resolve @rpath/libllama-common.0.dylib and died.
  fs.rmSync(dest, { recursive: true, force: true });
  fs.mkdirSync(dest, { recursive: true });

  if (IS_WIN) {
    const r = spawnSync("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command",
      `Expand-Archive -LiteralPath '${archive}' -DestinationPath '${dest}' -Force`], { stdio: "pipe" });
    if (r.status !== 0) throw new Error("Expand-Archive failed: " + r.stderr);
  } else {
    const r = spawnSync("tar", ["-xzf", archive, "-C", dest], { stdio: "pipe" });
    if (r.status !== 0) throw new Error("tar extraction failed: " + r.stderr);
  }

  const bin = findServerBinary(dest);
  if (!bin) throw new Error("llama-server binary not found after extraction");
  if (!IS_WIN) {
    try { fs.chmodSync(bin, 0o755); } catch (_) {}
    // Clear the quarantine flag so Gatekeeper does not block the unsigned binary.
    spawnSync("xattr", ["-dr", "com.apple.quarantine", dest], { stdio: "ignore" });
  }
  return bin;
}

function physicalCores() {
  if (!IS_WIN) return null;
  try {
    const r = spawnSync("powershell.exe", ["-NoProfile", "-Command",
      "(Get-CimInstance Win32_Processor | Measure-Object -Property NumberOfCores -Sum).Sum"], { encoding: "utf8" });
    const n = parseInt((r.stdout || "").trim(), 10);
    return n >= 2 ? n : null;
  } catch (_) { return null; }
}

async function startLlama() {
  if (await llamaAlive()) {
    log(`Reusing llama-server already on :${LLAMA_PORT} (model ${status.modelId})`);
    return;
  }
  const bin = extractLlama();
  const model = path.join(INSTALL_DIR, "models", MODEL_FILE);
  copyIfNeeded(path.join(AGENT_DIR, "models", MODEL_FILE), model, MODEL.label);

  status.detail = "Starting local AI engine...";
  log(status.detail);
  const ctx = process.env.QWEN_CONTEXT_SIZE || "32768";
  const args = ["-m", model, "--host", "127.0.0.1", "--port", String(LLAMA_PORT),
    "--alias", EXPECTED_MODEL_ID, "-c", ctx, "--parallel", "1",
    "--jinja", "--reasoning", "off",
    "--cache-reuse", "256", "-fa", "on", "--cache-type-k", "q8_0", "--cache-type-v", "q8_0"];
  // Qwen uses an external tool-call template; Granite carries its own inside the GGUF.
  if (TEMPLATE_FILE) {
    const template = path.join(INSTALL_DIR, "templates", TEMPLATE_FILE);
    copyIfNeeded(path.join(AGENT_DIR, "assets", "templates", TEMPLATE_FILE), template, "chat template");
    args.push("--chat-template-file", template);
  }
  if (!IS_WIN && process.arch === "arm64") args.push("-ngl", "999");
  if (IS_WIN) {
    const cores = physicalCores();
    if (cores) args.push("-t", String(cores));
    if ((process.env.QWEN_LLAMA_BACKEND || "cpu").toLowerCase() === "vulkan") {
      args.push("-ngl", "999");
      const i = args.indexOf("on", args.indexOf("-fa"));
      // vulkan: keep flash attention off and default KV types (known-good config)
      args.splice(args.indexOf("-fa"), 2);
      ["--cache-type-k", "--cache-type-v"].forEach((k) => {
        const j = args.indexOf(k); if (j >= 0) args.splice(j, 2);
      });
    }
  }
  const logDir = path.join(INSTALL_DIR, "logs");
  fs.mkdirSync(logDir, { recursive: true });
  // Write the engine log onto the USB drive so its startup errors (e.g. a rejected
  // flag, a missing DLL, or a Defender block) are visible without access to the PC.
  const engineLog = path.join(UI_DIR, "last-run-engine.log");
  log("llama-server command: " + bin + " " + args.join(" "));
  const out = fs.openSync(engineLog, "w");
  fs.writeSync(out, `# ${bin} ${args.join(" ")}\n`);
  llamaProc = spawn(bin, args, { stdio: ["ignore", out, out] });
  llamaProc.on("exit", (code) => log(`llama-server exited (${code})`));

  const tailEngineLog = () => {
    try { return fs.readFileSync(engineLog, "utf8").split("\n").slice(-12).join("\n"); }
    catch (_) { return "(no engine log)"; }
  };

  for (let i = 0; i < 180; i++) {
    await new Promise((r) => setTimeout(r, 1000));
    if (await llamaAlive()) { log("llama-server ready"); return; }
    if (llamaProc.exitCode !== null) {
      throw new Error("The AI engine quit during startup (exit " + llamaProc.exitCode + ").\nEngine log tail:\n" + tailEngineLog());
    }
  }
  throw new Error("The AI engine did not become ready in 3 minutes.\nEngine log tail:\n" + tailEngineLog());
}

async function setup() {
  try {
    loadCatalog();
    status.step = "engine";
    await startLlama();
    status.step = "ready";
    status.ready = true;
    status.detail = "";
  } catch (e) {
    status.error = String(e.message || e);
    status.step = "error";
    log("SETUP ERROR: " + status.error);
  }
}

// ---------- script execution ----------
function runScript(entry, extraArgs) {
  return new Promise((resolve) => {
    const file = scriptAbsPath(entry);
    const args = extraArgs || [];
    let cmd, cmdArgs;
    if (PLATFORM === "windows") {
      cmd = "powershell.exe";
      cmdArgs = ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", file, ...args];
    } else {
      cmd = "bash";
      cmdArgs = [file, ...args];
    }
    execCollect(cmd, cmdArgs, resolve);
  });
}

function runShell(command) {
  return new Promise((resolve) => {
    if (PLATFORM === "windows") {
      execCollect("powershell.exe", ["-NoProfile", "-ExecutionPolicy", "Bypass", "-Command", command], resolve);
    } else {
      execCollect("bash", ["-c", command], resolve);
    }
  });
}

function execCollect(cmd, args, resolve) {
  let outBuf = "";
  let proc;
  try {
    proc = spawn(cmd, args, { stdio: ["ignore", "pipe", "pipe"] });
  } catch (e) {
    return resolve({ code: -1, output: "Failed to start: " + e.message });
  }
  const timer = setTimeout(() => { try { proc.kill(); } catch (_) {} outBuf += "\n[timed out after 10 minutes]"; }, 600000);
  proc.stdout.on("data", (d) => (outBuf += d));
  proc.stderr.on("data", (d) => (outBuf += d));
  proc.on("close", (code) => {
    clearTimeout(timer);
    if (outBuf.length > 30000) outBuf = outBuf.slice(0, 15000) + "\n...[truncated]...\n" + outBuf.slice(-15000);
    resolve({ code, output: outBuf });
  });
}

// ---------- large-files scan + delete ----------
function defaultScanRoot() {
  return IS_WIN ? path.join(os.homedir()) : path.join(os.homedir());
}

// Directories never worth scanning (slow, system, or noise) - keeps the walk fast and safe.
function isSkippableDir(name) {
  const n = name.toLowerCase();
  if (IS_WIN) return ["windows", "$recycle.bin", "system volume information", "program files", "program files (x86)", "programdata"].includes(n);
  return n === "system" || n === "private" || n === ".trash";
}

function scanLargeFiles(root, minBytes, limit) {
  const results = [];
  let visited = 0;
  const MAX_VISIT = 400000; // bound the walk so a huge tree can't hang the server
  const stack = [root];
  while (stack.length) {
    const dir = stack.pop();
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); }
    catch (_) { continue; } // unreadable (perms) - skip quietly
    for (const ent of entries) {
      if (++visited > MAX_VISIT) { stack.length = 0; break; }
      const full = path.join(dir, ent.name);
      if (ent.isSymbolicLink()) continue;
      if (ent.isDirectory()) {
        if (!isSkippableDir(ent.name)) stack.push(full);
      } else if (ent.isFile()) {
        let st;
        try { st = fs.statSync(full); } catch (_) { continue; }
        if (st.size >= minBytes) results.push({ path: full, size: st.size });
      }
    }
  }
  results.sort((a, b) => b.size - a.size);
  return { files: results.slice(0, limit), totalFound: results.length, visited };
}

// Paths we refuse to delete no matter what the UI asks.
function isProtectedPath(p) {
  let abs;
  try { abs = fs.realpathSync(path.dirname(p)) + path.sep + path.basename(p); } catch (_) { abs = path.resolve(p); }
  const a = abs.toLowerCase();
  // Never touch the USB drive itself or our own install dir.
  if (a.startsWith(DRIVE_ROOT.toLowerCase())) return true;
  if (a.startsWith(INSTALL_DIR.toLowerCase())) return true;
  const roots = IS_WIN
    ? [(process.env.windir || "c:\\windows"), "c:\\program files", "c:\\program files (x86)", "c:\\programdata", "c:\\$recycle.bin"]
    : ["/system", "/usr", "/bin", "/sbin", "/etc", "/var", "/library", "/applications", "/private/etc", "/private/var"];
  return roots.some((r) => a.startsWith(r.toLowerCase()));
}

function deleteFilesPermanently(paths) {
  const logDir = path.join(TECHKIT_DIR, "collections");
  try { fs.mkdirSync(logDir, { recursive: true }); } catch (_) {}
  const logFile = path.join(logDir, `${os.hostname()}-file-deletions-${Date.now()}.log`);
  const lines = [];
  const results = [];
  let freed = 0;
  for (const p of paths) {
    let st;
    try { st = fs.statSync(p); } catch (e) {
      results.push({ path: p, ok: false, error: "not found" }); continue;
    }
    if (!st.isFile()) { results.push({ path: p, ok: false, error: "not a file" }); continue; }
    if (isProtectedPath(p)) { results.push({ path: p, ok: false, error: "protected/system path - refused" }); continue; }
    try {
      fs.rmSync(p, { force: true });
      freed += st.size;
      results.push({ path: p, ok: true, size: st.size });
      lines.push(`${new Date().toISOString()}  DELETED  ${st.size}  ${p}`);
    } catch (e) {
      results.push({ path: p, ok: false, error: String(e.message || e) });
      lines.push(`${new Date().toISOString()}  FAILED   ${p}  ${e.message}`);
    }
  }
  try { fs.writeFileSync(logFile, lines.join("\n") + "\n"); } catch (_) {}
  log(`permanent delete: ${results.filter((r) => r.ok).length}/${paths.length} files, ${(freed / 1048576).toFixed(0)} MB freed`);
  return { results, freedBytes: freed, logFile };
}

// ---------- assistant (chat + tool loop) ----------
function buildSystemPrompt() {
  let catalogMd = "";
  try {
    catalogMd = fs.readFileSync(path.join(TECHKIT_DIR, `catalog-${PLATFORM}.md`), "utf8")
      .replace(/__TECHKIT__/g, TECHKIT_DIR)
      .replace(/__CATALOG__/g, path.join(TECHKIT_DIR, "catalog.json"));
  } catch (_) {}
  return [
    "You are a computer technician assistant running locally on a customer machine inside the Tech Tool app.",
    `Machine: ${os.hostname()}, ${PLATFORM}, ${os.arch()}, ${Math.round(os.totalmem() / 1073741824)} GB RAM.`,
    "You have two tools: run_techkit_script (preferred - vetted diagnostic/repair scripts) and run_shell (raw command; needs user approval).",
    "PRIME RULE: match the user's complaint to a TechKit script by its catalog id, call run_techkit_script, then interpret the output. Lead with [!] findings, then a short diagnosis and one next step. Keep replies under 120 words.",
    "Destructive scripts dry-run by default: run the dry-run first, show what would change, and only add the force flag after the user explicitly agrees. Administrator accounts can never be removed; the scripts enforce this - never work around it.",
    "Use exact numbers and paths from tool output. Never invent results. If a tool fails, show the error.",
    "Script ids and purposes:",
    catalogMd,
  ].join("\n");
}

const TOOLS_SPEC = () => [
  {
    type: "function",
    function: {
      name: "run_techkit_script",
      description: "Run a vetted TechKit script by catalog id and return its output. Read-only scripts run immediately; force/destructive flags require user approval.",
      parameters: {
        type: "object",
        properties: {
          id: { type: "string", description: "catalog id, e.g. " + catalog.slice(0, 3).map((s) => s.id).join(", ") },
          args: { type: "array", items: { type: "string" }, description: "extra command-line arguments (optional)" },
        },
        required: ["id"],
      },
    },
  },
  {
    type: "function",
    function: {
      name: "run_shell",
      description: "Run a raw shell command (PowerShell on Windows, bash on macOS). Always requires user approval. Prefer run_techkit_script when one fits.",
      parameters: {
        type: "object",
        properties: { command: { type: "string" } },
        required: ["command"],
      },
    },
  },
];

async function llamaChat(messages, opts = {}) {
  const payload = {
    model: status.modelId,
    messages,
    temperature: 0.2,
    top_p: 0.9,
    max_tokens: parseInt(process.env.QWEN_MAX_OUTPUT_TOKENS || "4096", 10),
  };
  if (!opts.noTools) payload.tools = TOOLS_SPEC();
  const body = JSON.stringify(payload);
  const r = await fetchJson(`${LLAMA_URL}/v1/chat/completions`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "Content-Length": Buffer.byteLength(body) },
    body,
  });
  if (!r.json || !r.json.choices) throw new Error("AI engine error: " + (r.raw || r.status));
  return r.json.choices[0].message;
}

// Analyze raw diagnostic output (no tools - the model just interprets the text given).
async function analyzeOutput(title, output, instruction) {
  const toolList = (catalog || []).map((s) => `- ${s.title || s.path.split("/").pop()}: ${s.summary}`).join("\n");
  const sys = [
    "You are an expert computer technician analyzing the output of a diagnostic tool.",
    "Be concise and practical. Structure your answer with these exact section headers, each on its own line:",
    "SUMMARY - one or two plain-English sentences on overall health.",
    "FINDINGS - bullet the notable items, especially anything marked [!]; say why each matters. Use the literal word ERROR, FAILED, WARNING, or CRITICAL when something is actually wrong, so it stands out.",
    "LIKELY CAUSE - if something is wrong, the most probable explanation.",
    "NEXT STEPS - this section is the most important. Give 3 to 5 specific, prioritized, actionable steps a technician can take. Number them. For each step: say exactly what to do, and one short clause on why or what to expect. Order them most-likely-to-help first. Include at least one concrete action even if the system looks healthy (e.g. routine maintenance or what to monitor).",
    "",
    "These Tech Tool tools are available on this machine. When a next step can be done by one of them, refer to it by its EXACT name in double asterisks, e.g. **Disk Health**, so it becomes a clickable shortcut:",
    toolList,
    "",
    "Only use facts present in the output. Do not invent data. Keep the whole reply under 280 words.",
  ].join("\n");
  let text = String(output || "");
  if (text.length > 16000) text = text.slice(0, 8000) + "\n...[output truncated for analysis]...\n" + text.slice(-8000);
  const user = `Diagnostic tool: ${title || "(unknown)"}\n\n--- OUTPUT ---\n${text}\n--- END OUTPUT ---\n\n${instruction || "Summarize and analyze this output."}`;
  const msg = await llamaChat([{ role: "system", content: sys }, { role: "user", content: user }], { noTools: true });
  return msg.content || "(no analysis returned)";
}

// Conversational follow-up Q&A grounded in a diagnostic report + its analysis.
async function answerFollowup(title, output, analysis, history, question) {
  const toolList = (catalog || []).map((s) => `- ${s.title || s.path.split("/").pop()}: ${s.summary}`).join("\n");
  const sys = [
    "You are an expert computer technician helping another technician understand a diagnostic report.",
    "Answer the follow-up question directly and concisely in plain English (usually under 180 words; go longer only when truly needed).",
    "Ground every answer ONLY in the report output and analysis provided, plus general technical knowledge. If a specific value isn't in the data, say so and suggest which tool would find it.",
    "When a relevant Tech Tool tool exists, name it in double asterisks, e.g. **Disk Health**, so it becomes a clickable shortcut.",
    "Do not invent values from the machine. Be practical and actionable.",
    "",
    "Available tools on this machine:",
    toolList,
  ].join("\n");
  let text = String(output || "");
  if (text.length > 12000) text = text.slice(0, 6000) + "\n...[output truncated]...\n" + text.slice(-6000);
  const ctx = `Diagnostic tool: ${title || "(unknown)"}\n\n--- REPORT OUTPUT ---\n${text}\n--- END OUTPUT ---` +
    (analysis && String(analysis).trim() ? `\n\n--- EARLIER AI ANALYSIS ---\n${String(analysis)}\n--- END ANALYSIS ---` : "");
  const messages = [
    { role: "system", content: sys },
    { role: "user", content: ctx },
    { role: "assistant", content: "I've reviewed the report. What would you like to know?" },
  ];
  for (const h of (Array.isArray(history) ? history : []).slice(-6)) {
    if (h && h.q) messages.push({ role: "user", content: String(h.q) });
    if (h && h.a) messages.push({ role: "assistant", content: String(h.a) });
  }
  messages.push({ role: "user", content: String(question) });
  const msg = await llamaChat(messages, { noTools: true });
  return msg.content || "(no answer returned)";
}

function fmtUptime(sec) {
  const d = Math.floor(sec / 86400), h = Math.floor((sec % 86400) / 3600), m = Math.floor((sec % 3600) / 60);
  const p = [];
  if (d) p.push(d + "d");
  if (h) p.push(h + "h");
  p.push(m + "m");
  return p.join(" ");
}
// Run a short command for a single fact; returns "" on any failure/timeout (best-effort).
function probe(cmd, args, ms) {
  try {
    const r = spawnSync(cmd, args, { timeout: ms || 3000, encoding: "utf8", stdio: ["ignore", "pipe", "ignore"] });
    if (r && r.status === 0 && r.stdout) return r.stdout.trim();
  } catch (_) {}
  return "";
}
// Pertinent client-computer details for a ticket. Fast os-module facts always; model/serial
// are best-effort and silently omitted if the probe fails or times out.
function gb(bytes, dp) { const v = bytes / 1073741824; return dp === 0 ? String(Math.round(v)) : v.toFixed(dp === undefined ? 1 : dp); }

function getMachineInfo() {
  let osLine = `${PLATFORM === "windows" ? "Windows" : "macOS"} (${process.platform} ${os.release()})`; // fallback
  let model = "", serial = "", memUsed = null, disk = null;
  try {
    if (PLATFORM === "windows") {
      const ps = "$o=Get-CimInstance Win32_OperatingSystem;$c=Get-CimInstance Win32_ComputerSystem;$b=Get-CimInstance Win32_BIOS;$d=Get-CimInstance Win32_LogicalDisk -Filter \"DeviceID='C:'\";$a=@(Get-ItemProperty 'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKLM:\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*' -ErrorAction SilentlyContinue|Where-Object {$_.DisplayName}).Count;'OS='+$o.Caption+' '+$o.Version;'Model='+$c.Manufacturer+' '+$c.Model;'Serial='+$b.SerialNumber;'MemTotalKB='+$o.TotalVisibleMemorySize;'MemFreeKB='+$o.FreePhysicalMemory;'DiskTotal='+$d.Size;'DiskFree='+$d.FreeSpace;'Apps='+$a";
      const out = probe("powershell", ["-NoProfile", "-Command", ps], 7000);
      const g = (re) => { const m = out.match(re); return m ? m[1].trim() : ""; };
      if (g(/OS=(.+)/)) osLine = g(/OS=(.+)/);
      model = g(/Model=(.+)/); serial = g(/Serial=(.+)/);
      const mt = parseInt(g(/MemTotalKB=(\d+)/), 10), mf = parseInt(g(/MemFreeKB=(\d+)/), 10);
      if (mt && mf) memUsed = (mt - mf) * 1024;
      const dt = parseInt(g(/DiskTotal=(\d+)/), 10), dfr = parseInt(g(/DiskFree=(\d+)/), 10);
      if (dt) disk = { total: dt, used: dt - dfr, free: dfr };
    } else {
      const ver = probe("sw_vers", ["-productVersion"], 2000);
      const build = probe("sw_vers", ["-buildVersion"], 2000);
      if (ver) osLine = `macOS ${ver}${build ? ` (build ${build})` : ""}`;
      const sp = probe("system_profiler", ["SPHardwareDataType"], 4000);
      model = (sp.match(/Model Name:\s*(.+)/) || [])[1] || (sp.match(/Model Identifier:\s*(.+)/) || [])[1] || "";
      serial = (sp.match(/Serial Number \(system\):\s*(.+)/) || [])[1] || "";
      const vm = probe("vm_stat", [], 2000);
      if (vm) {
        const pg = parseInt(probe("sysctl", ["-n", "hw.pagesize"], 1000) || "4096", 10);
        const pv = (re) => { const m = vm.match(re); return m ? parseInt(m[1], 10) : 0; };
        const used = (pv(/Pages active:\s+(\d+)/) + pv(/Pages wired down:\s+(\d+)/) + pv(/Pages occupied by compressor:\s+(\d+)/)) * pg;
        if (used) memUsed = used;
      }
      const df = probe("df", ["-k", "/"], 2000);
      const row = (df.split("\n")[1] || "").trim().split(/\s+/);
      if (row.length >= 4 && parseInt(row[1], 10)) {
        const tKB = parseInt(row[1], 10), aKB = parseInt(row[3], 10);
        disk = { total: tKB * 1024, used: (tKB - aKB) * 1024, free: aKB * 1024 };
      }
    }
  } catch (_) {}

  const L = [];
  L.push(`- Hostname: ${os.hostname()}`);
  if (model && model.trim()) L.push(`- Model: ${model.trim()}`);
  if (serial && serial.trim() && !/to be filled|default string/i.test(serial)) L.push(`- Serial: ${serial.trim()}`);
  L.push(`- OS: ${osLine}`);
  const cpu = (os.cpus()[0] || {}).model;
  if (cpu) L.push(`- CPU: ${cpu.trim()} (${os.cpus().length} logical cores)`);
  L.push(`- Memory: ${gb(os.totalmem(), 0)} GB total${memUsed ? ` (${gb(memUsed)} GB in use)` : ""}`);
  if (disk && disk.total) L.push(`- Storage: ${gb(disk.total, 0)} GB total, ${gb(disk.used)} GB used (${gb(disk.free)} GB free)`);
  L.push(`- Uptime: ${fmtUptime(os.uptime())}`);
  try { L.push(`- Signed-in user: ${os.userInfo().username}`); } catch (_) {}
  return L.join("\n");
}

// Full installed-application list for the ticket. macOS: app bundle names in /Applications
// (+ Utilities). Windows: registry Uninstall display names + versions (NOT Win32_Product,
// which is slow and can trigger MSI repairs). Returns "N total:\n<comma list>" or "".
function getInstalledApps() {
  try {
    if (PLATFORM === "windows") {
      const ps = "@(Get-ItemProperty 'HKLM:\\Software\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*','HKLM:\\Software\\Wow6432Node\\Microsoft\\Windows\\CurrentVersion\\Uninstall\\*' -ErrorAction SilentlyContinue | Where-Object {$_.DisplayName} | ForEach-Object { if ($_.DisplayVersion) { $_.DisplayName+' '+$_.DisplayVersion } else { [string]$_.DisplayName } }) | Sort-Object -Unique";
      const out = probe("powershell", ["-NoProfile", "-Command", ps], 8000);
      const list = out.split("\n").map((s) => s.trim()).filter(Boolean);
      return list.length ? `${list.length} total:\n${list.join(", ")}` : "";
    }
    let names = [];
    try { names = fs.readdirSync("/Applications").filter((f) => f.endsWith(".app")).map((f) => f.replace(/\.app$/, "")); } catch (_) {}
    try { names = names.concat(fs.readdirSync("/Applications/Utilities").filter((f) => f.endsWith(".app")).map((f) => f.replace(/\.app$/, "") + " (Utilities)")); } catch (_) {}
    names.sort((a, b) => a.toLowerCase().localeCompare(b.toLowerCase()));
    return names.length ? `${names.length} total:\n${names.join(", ")}` : "";
  } catch (_) { return ""; }
}

// Native OS folder picker (no browser can return a real absolute path). Runs the dialog on
// this machine and resolves with { path } / { cancelled } / { error }. Async so the server
// stays responsive while the dialog is open.
function pickFolder(promptText) {
  const label = String(promptText || "Choose a folder").replace(/["'\r\n]/g, " ");
  return new Promise((resolve) => {
    let cmd, args;
    if (IS_WIN) {
      const ps = "Add-Type -AssemblyName System.Windows.Forms | Out-Null; $f = New-Object System.Windows.Forms.FolderBrowserDialog; $f.Description = '" + label + "'; $f.ShowNewFolderButton = $true; if ($f.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) { [Console]::Out.Write($f.SelectedPath) }";
      cmd = "powershell"; args = ["-NoProfile", "-STA", "-Command", ps];
    } else {
      const script = 'try\nset f to choose folder with prompt "' + label + '"\nPOSIX path of f\non error number -128\nreturn ""\nend try';
      cmd = "osascript"; args = ["-e", script];
    }
    let out = "", p;
    try { p = spawn(cmd, args, { stdio: ["ignore", "pipe", "ignore"] }); }
    catch (e) { return resolve({ error: String(e.message || e) }); }
    const timer = setTimeout(() => { try { p.kill(); } catch (_) {} }, 180000);
    p.stdout.on("data", (d) => (out += d));
    p.on("close", () => { clearTimeout(timer); const pth = out.trim(); resolve(pth ? { path: pth } : { cancelled: true }); });
    p.on("error", (e) => { clearTimeout(timer); resolve({ error: String(e.message || e) }); });
  });
}

// Turn the session activity log into a closing ticket note.
async function buildTicketSummary() {
  const fmtTimeShort = (iso) => { try { return new Date(iso).toLocaleTimeString(); } catch (_) { return iso; } };
  const lines = activity.map((a) => {
    if (a.kind === "ask") return `[${fmtTimeShort(a.t)}] Technician asked: "${a.text}"`;
    if (a.kind === "delete") return `[${fmtTimeShort(a.t)}] Deleted ${a.count} file(s), freed ${a.freedMB} MB`;
    if (a.kind === "shell") return `[${fmtTimeShort(a.t)}] Ran shell command: ${a.command} (exit ${a.code})${a.digest ? "\n  " + a.digest.replace(/\n/g, "\n  ") : ""}`;
    const who = a.via === "assistant" ? " (via AI)" : "";
    return `[${fmtTimeShort(a.t)}] Ran ${a.tool}${a.args && a.args.length ? " " + a.args.join(" ") : ""}${who} (exit ${a.code})${a.digest ? "\n  " + a.digest.replace(/\n/g, "\n  ") : ""}`;
  });
  let logText = lines.join("\n");
  if (logText.length > 14000) logText = logText.slice(0, 14000) + "\n…[older activity trimmed]…";

  const sys = [
    "You are an IT technician writing the closing note for a support ticket, based on a log of what was done during the session.",
    "Write a concise, professional summary ready to paste into a ticketing system. Use these section headers, each on its own line:",
    "ISSUE - the apparent reason for the visit, inferred from what was checked/asked. One or two sentences.",
    "ACTIONS TAKEN - bulleted list of the diagnostics run and changes made, in plain language (not script filenames).",
    "FINDINGS - the notable results, especially anything flagged with [!]; call out errors/failures clearly. If nothing notable, say the system checked out.",
    "RESOLUTION - what state things are in now / what was fixed.",
    "FOLLOW-UP - recommended next steps or items to monitor, if any.",
    "Be factual — only state what the log supports. Do not invent results. Keep it under 300 words.",
  ].join("\n");
  const user = `Machine: ${os.hostname()} (${PLATFORM}). Session activity log:\n\n${logText}`;
  const msg = await llamaChat([{ role: "system", content: sys }, { role: "user", content: user }], { noTools: true });
  return msg.content || "(no summary returned)";
}

function getSession(id) {
  if (!sessions.has(id)) {
    sessions.set(id, { messages: [{ role: "system", content: buildSystemPrompt() }], pending: null });
  }
  return sessions.get(id);
}

function describeToolCall(name, args) {
  if (name === "run_techkit_script") {
    const entry = scriptById(args.id);
    return { title: entry ? entry.path.split("/").pop() : args.id, detail: (args.args || []).join(" ") };
  }
  return { title: "shell command", detail: args.command || "" };
}

async function executeToolCall(name, args) {
  if (name === "run_techkit_script") {
    const entry = scriptById(args.id);
    if (!entry) return { code: -1, output: `Unknown script id '${args.id}'. Valid ids: ${catalog.map((s) => s.id).join(", ")}` };
    const r = await runScript(entry, args.args || []);
    logActivity({ kind: "tool", via: "assistant", tool: entry.title || entry.path.split("/").pop(), args: args.args || [], code: r.code, digest: digestOutput(r.output) });
    return r;
  }
  if (name === "run_shell") {
    const r = await runShell(args.command || "");
    logActivity({ kind: "shell", via: "assistant", command: args.command || "", code: r.code, digest: digestOutput(r.output) });
    return r;
  }
  return { code: -1, output: "Unknown tool " + name };
}

function toolNeedsApproval(name, args) {
  if (name === "run_shell") return "Raw shell commands always need your approval.";
  const entry = scriptById(args.id);
  if (entry && argsNeedConfirm(args.args)) return "This call uses a force/act flag on a script that changes the system.";
  return null;
}

// Run the agent loop until we get a plain reply or need user approval.
async function agentLoop(session, events) {
  for (let iter = 0; iter < 8; iter++) {
    const msg = await llamaChat(session.messages);
    if (msg.tool_calls && msg.tool_calls.length) {
      session.messages.push(msg);
      const tc = msg.tool_calls[0]; // handle sequentially; extra calls answered on next iteration
      for (let i = 1; i < msg.tool_calls.length; i++) {
        session.messages.push({ role: "tool", tool_call_id: msg.tool_calls[i].id, content: "Skipped: one tool call at a time. Re-issue if still needed." });
      }
      let args = {};
      try { args = JSON.parse(tc.function.arguments || "{}"); } catch (_) {}
      const approvalReason = toolNeedsApproval(tc.function.name, args);
      if (approvalReason) {
        session.pending = { id: tc.id, name: tc.function.name, args };
        return { type: "confirm", call: { ...describeToolCall(tc.function.name, args), name: tc.function.name, args, reason: approvalReason }, events };
      }
      const desc = describeToolCall(tc.function.name, args);
      log(`agent tool: ${tc.function.name} ${JSON.stringify(args)}`);
      const result = await executeToolCall(tc.function.name, args);
      log(`  -> exit ${result.code}, ${(result.output || "").length} bytes`);
      events.push({ type: "tool", ...desc, output: result.output, code: result.code });
      session.messages.push({ role: "tool", tool_call_id: tc.id, content: result.output || "(no output)" });
      continue;
    }
    return { type: "reply", content: msg.content || "(empty reply)", events };
  }
  return { type: "reply", content: "Stopped after 8 tool steps - tell me how to proceed.", events };
}

// ---------- HTTP ----------
function readBody(req) {
  return new Promise((resolve) => {
    let b = "";
    req.on("data", (c) => (b += c));
    req.on("end", () => { try { resolve(JSON.parse(b || "{}")); } catch (_) { resolve({}); } });
  });
}

const NO_CACHE = { "Cache-Control": "no-store, no-cache, must-revalidate", "Pragma": "no-cache", "Expires": "0" };

function send(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, { "Content-Type": "application/json", ...NO_CACHE });
  res.end(body);
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://127.0.0.1:${UI_PORT}`);
  try {
    if (req.method === "GET" && (url.pathname === "/" || url.pathname === "/index.html")) {
      res.writeHead(200, { "Content-Type": "text/html; charset=utf-8", ...NO_CACHE });
      return res.end(fs.readFileSync(path.join(UI_DIR, "public", "index.html")));
    }
    if (req.method === "GET" && url.pathname === "/api/status") {
      return send(res, 200, {
        ...status,
        activityCount: activity.length,
        machine: { hostname: os.hostname(), platform: PLATFORM, arch: os.arch(), ramGB: Math.round(os.totalmem() / 1073741824) },
      });
    }
    if (req.method === "GET" && url.pathname === "/api/catalog") {
      return send(res, 200, { scripts: catalog || [] });
    }
    if (req.method === "POST" && url.pathname === "/api/run") {
      const { id, args } = await readBody(req);
      const entry = scriptById(id);
      if (!entry) return send(res, 404, { error: "unknown script id" });
      log(`guided run: ${id} ${(args || []).join(" ")}`);
      const result = await runScript(entry, args || []);
      logActivity({ kind: "tool", via: "guided", tool: entry.title || entry.path.split("/").pop(), args: args || [], code: result.code, digest: digestOutput(result.output) });
      return send(res, 200, result);
    }
    // Run a script in its OWN visible PowerShell window so the tech watches live progress
    // (used for long destructive applies like the profile cleanup). Windows only; elsewhere
    // it falls back to a normal captured run so dev/testing still works.
    if (req.method === "POST" && url.pathname === "/api/runwindow") {
      const { id, args } = await readBody(req);
      const entry = scriptById(id);
      if (!entry) return send(res, 404, { error: "unknown script id" });
      const file = scriptAbsPath(entry);
      const xargs = args || [];
      log(`windowed run: ${id} ${xargs.join(" ")}`);
      logActivity({ kind: "tool", via: "guided-window", tool: entry.title || entry.path.split("/").pop(), args: xargs, code: 0, digest: "(running live in its own PowerShell window)" });
      if (IS_WIN) {
        // -NoExit keeps the window open when finished so the final totals stay readable.
        // The new process inherits this server's elevation, so -Force has admin rights.
        const psArgs = ["-NoExit", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", file, ...xargs];
        try {
          const child = spawn("cmd", ["/c", "start", "Tech Tool cleanup", "powershell", ...psArgs], { detached: true, stdio: "ignore" });
          child.unref();
          return send(res, 200, { windowed: true });
        } catch (e) {
          return send(res, 500, { error: "could not open PowerShell window: " + e.message });
        }
      }
      const result = await runScript(entry, xargs);
      return send(res, 200, { windowed: false, code: result.code, output: result.output });
    }
    if (req.method === "POST" && url.pathname === "/api/analyze") {
      if (!status.ready) return send(res, 503, { error: "AI engine not ready yet" });
      const { title, output, instruction } = await readBody(req);
      if (!output || !String(output).trim()) return send(res, 400, { error: "nothing to analyze" });
      log(`analyze: ${title || "(untitled)"} (${String(output).length} chars)`);
      const analysis = await analyzeOutput(title, output, instruction);
      return send(res, 200, { analysis });
    }
    if (req.method === "POST" && url.pathname === "/api/followup") {
      if (!status.ready) return send(res, 503, { error: "AI engine not ready yet" });
      const { title, output, analysis, question, history } = await readBody(req);
      if (!question || !String(question).trim()) return send(res, 400, { error: "no question" });
      if (!output || !String(output).trim()) return send(res, 400, { error: "no report to ask about" });
      log(`followup: ${title || "(untitled)"} — "${String(question).slice(0, 120)}"`);
      const answer = await answerFollowup(title, output, analysis, history, question);
      logActivity({ kind: "ask", text: `(about ${title || "a report"}) ${String(question).slice(0, 240)}` });
      return send(res, 200, { answer });
    }
    if (req.method === "POST" && url.pathname === "/api/savereport") {
      const { title, output, analysis, followups } = await readBody(req);
      const dir = path.join(DRIVE_ROOT, "Reports");
      try { fs.mkdirSync(dir, { recursive: true }); } catch (_) {}
      const safe = String(title || "report").replace(/[^A-Za-z0-9]+/g, "-").replace(/^-+|-+$/g, "").slice(0, 40) || "report";
      const stamp = new Date().toISOString().replace(/[:.]/g, "-").slice(0, 19);
      const file = path.join(dir, `${os.hostname()}-${safe}-${stamp}.txt`);
      const parts = [
        `Tech Tool report`,
        `Tool    : ${title || "(unknown)"}`,
        `Host    : ${os.hostname()}`,
        `Saved   : ${new Date().toString()}`,
        ``, `=== OUTPUT ===`, String(output || "(none)"),
      ];
      if (analysis && String(analysis).trim()) parts.push(``, `=== AI ANALYSIS ===`, String(analysis));
      if (Array.isArray(followups) && followups.length) {
        parts.push(``, `=== FOLLOW-UP Q&A ===`);
        for (const f of followups) { if (f && f.q) parts.push(`Q: ${String(f.q)}`, `A: ${String(f.a || "")}`, ``); }
      }
      try {
        fs.writeFileSync(file, parts.join("\n") + "\n");
        log(`saved report: ${file}`);
        return send(res, 200, { ok: true, file });
      } catch (e) {
        return send(res, 500, { error: "Could not write to USB: " + e.message });
      }
    }
    if (req.method === "POST" && url.pathname === "/api/chat") {
      if (!status.ready) return send(res, 503, { error: "AI engine not ready yet" });
      const { session: sid, message } = await readBody(req);
      const session = getSession(sid || "default");
      if (session.pending) return send(res, 409, { error: "approval pending" });
      session.messages.push({ role: "user", content: String(message || "") });
      logActivity({ kind: "ask", text: String(message || "").slice(0, 300) });
      const out = await agentLoop(session, []);
      return send(res, 200, out);
    }
    if (req.method === "POST" && url.pathname === "/api/confirm") {
      const { session: sid, approve } = await readBody(req);
      const session = getSession(sid || "default");
      if (!session.pending) return send(res, 400, { error: "nothing pending" });
      const pending = session.pending;
      session.pending = null;
      const events = [];
      if (approve) {
        const desc = describeToolCall(pending.name, pending.args);
        log(`approved: ${pending.name} ${JSON.stringify(pending.args)}`);
        const result = await executeToolCall(pending.name, pending.args);
        events.push({ type: "tool", ...desc, output: result.output, code: result.code });
        session.messages.push({ role: "tool", tool_call_id: pending.id, content: result.output || "(no output)" });
      } else {
        session.messages.push({ role: "tool", tool_call_id: pending.id, content: "User DENIED this action. Do not retry it; ask what they want instead." });
      }
      const out = await agentLoop(session, events);
      return send(res, 200, out);
    }
    if (req.method === "POST" && url.pathname === "/api/largefiles") {
      const body = await readBody(req);
      const root = body.path && String(body.path).trim() ? String(body.path).trim() : defaultScanRoot();
      const minMB = Math.max(1, parseInt(body.minMB, 10) || 200);
      const limit = Math.min(500, parseInt(body.limit, 10) || 200);
      if (!fs.existsSync(root)) return send(res, 400, { error: "Path not found: " + root });
      log(`largefiles scan: ${root} (>= ${minMB} MB)`);
      const r = scanLargeFiles(root, minMB * 1048576, limit);
      return send(res, 200, {
        root, minMB,
        files: r.files.map((f) => ({ path: f.path, sizeMB: +(f.size / 1048576).toFixed(1) })),
        totalFound: r.totalFound, scanned: r.visited,
      });
    }
    if (req.method === "POST" && url.pathname === "/api/deletefiles") {
      const body = await readBody(req);
      const paths = Array.isArray(body.paths) ? body.paths.filter((p) => typeof p === "string") : [];
      if (!paths.length) return send(res, 400, { error: "no paths provided" });
      const out = deleteFilesPermanently(paths);
      const okCount = out.results.filter((r) => r.ok).length;
      logActivity({ kind: "delete", count: okCount, freedMB: +(out.freedBytes / 1048576).toFixed(1) });
      return send(res, 200, { ...out, freedMB: +(out.freedBytes / 1048576).toFixed(1) });
    }
    if (req.method === "POST" && url.pathname === "/api/ticket") {
      if (!status.ready) return send(res, 503, { error: "AI engine not ready yet" });
      const header = `AUTO-GENERATED SUMMARY: Produced automatically by Tech Tool from the diagnostic session below — please review before relying on it. Generated ${new Date().toLocaleString()}.`;
      const machine = `CLIENT COMPUTER:\n${getMachineInfo()}`;
      const appsStr = getInstalledApps();
      const appsSection = appsStr ? `INSTALLED APPLICATIONS:\n${appsStr}\n` : "";
      const ai = activity.length
        ? await buildTicketSummary()
        : "ISSUE: No diagnostics have been run in this session yet.\nACTIONS TAKEN: None recorded.\nFINDINGS: None.\nRESOLUTION: None.\nFOLLOW-UP: Run a tool or two, then regenerate this summary.";
      return send(res, 200, { summary: `${header}\n${machine}\n${appsSection}${ai}` });
    }
    if (req.method === "POST" && url.pathname === "/api/pickfolder") {
      const body = await readBody(req);
      const r = await pickFolder(body.prompt);
      return send(res, 200, r);
    }
    if (req.method === "POST" && url.pathname === "/api/reset") {
      const { session: sid } = await readBody(req);
      if (sid) sessions.delete(sid);
      activity.length = 0; // clearing the session resets the activity log (and thus the ticket summary)
      log("Session cleared from UI — activity log reset.");
      return send(res, 200, { ok: true });
    }
    if (req.method === "POST" && url.pathname === "/api/exit") {
      log("Exit requested from UI — stopping the AI engine and shutting down.");
      send(res, 200, { ok: true });
      // Respond first, then stop llama-server and exit (mirrors the SIGINT handler).
      setTimeout(() => { try { if (llamaProc) llamaProc.kill(); } catch (_) {} process.exit(0); }, 350);
      return;
    }
    if (req.method === "POST" && url.pathname === "/api/uninstall") {
      log("Uninstall requested from UI — removing local install: " + INSTALL_DIR);
      try { if (llamaProc) llamaProc.kill(); } catch (_) {}
      llamaProc = null; status.ready = false;
      // Give llama-server a moment to release the model file (matters on Windows, where
      // deleting a file held open by a running process fails).
      await new Promise((r) => setTimeout(r, 700));
      let freedMB = 0;
      try { if (fs.existsSync(INSTALL_DIR)) freedMB = Math.round(dirSize(INSTALL_DIR) / 1048576); } catch (_) {}
      let lastErr = null;
      for (let i = 0; i < 3; i++) {
        try { fs.rmSync(INSTALL_DIR, { recursive: true, force: true, maxRetries: 3, retryDelay: 300 }); lastErr = null; break; }
        catch (e) { lastErr = e; await new Promise((r) => setTimeout(r, 500)); }
      }
      if (lastErr) return send(res, 500, { error: "Could not remove local files: " + lastErr.message });
      // Remove the parent ~/.tech-utility too if nothing else lives there.
      try { const parent = path.dirname(INSTALL_DIR); if (fs.existsSync(parent) && fs.readdirSync(parent).length === 0) fs.rmdirSync(parent); } catch (_) {}
      log(`Uninstall complete — removed ${freedMB} MB from ${INSTALL_DIR}`);
      send(res, 200, { ok: true, path: INSTALL_DIR, freedMB });
      // The engine is gone; this server can no longer function. Exit so the tech can unplug.
      setTimeout(() => process.exit(0), 1200);
      return;
    }
    send(res, 404, { error: "not found" });
  } catch (e) {
    log("HTTP error: " + (e.stack || e));
    send(res, 500, { error: String(e.message || e) });
  }
});
server.timeout = 0;
server.requestTimeout = 0;
server.headersTimeout = 0;

function openBrowser() {
  if (process.env.TECHTOOL_NO_BROWSER) return;
  const url = `http://127.0.0.1:${UI_PORT}`;
  if (IS_WIN) spawn("cmd", ["/c", "start", "", url], { stdio: "ignore", detached: true });
  else spawn("open", [url], { stdio: "ignore", detached: true });
}

server.on("error", (e) => {
  if (e.code === "EADDRINUSE") {
    // A Tech Tool instance is probably already running - just open the browser to it
    // rather than dying with a stack trace.
    log(`Port ${UI_PORT} is already in use - Tech Tool may already be running. Opening browser to the existing instance.`);
    console.log("\n  Tech Tool is already running. Your browser will open to it.");
    console.log("  If the page does not load, close all Tech Tool windows and try again.\n");
    openBrowser();
    setTimeout(() => process.exit(0), 1500);
  } else {
    console.error("Server error:", e.message);
    process.exit(1);
  }
});

server.listen(UI_PORT, "127.0.0.1", () => {
  log(`Tech Tool UI: http://127.0.0.1:${UI_PORT}`);
  setup();
  openBrowser();
});

process.on("SIGINT", () => {
  if (llamaProc) try { llamaProc.kill(); } catch (_) {}
  process.exit(0);
});
