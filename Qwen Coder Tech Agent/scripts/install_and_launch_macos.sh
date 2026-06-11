#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
ROOT_DIR="${SCRIPT_DIR:h}"
REAL_HOME="$HOME"
INSTALL_DIR="$REAL_HOME/.tech-utility/qwen-coder-tech-agent"
LEGACY_INSTALL_DIR="$REAL_HOME/.tech-utility/qwen-coder-codex"
QWEN_CODE_DIR="$INSTALL_DIR/qwen-code"
QWEN_HOME_DIR="$INSTALL_DIR/qwen-home"
QWEN_RUNTIME_DIR="$INSTALL_DIR/qwen-runtime"
LLAMA_DIR="$INSTALL_DIR/llama.cpp"
MODEL_DIR="$INSTALL_DIR/models"
TEMPLATE_DIR="$INSTALL_DIR/templates"
LOG_DIR="$INSTALL_DIR/logs"
RUN_DIR="$INSTALL_DIR/run"
WORK_ROOT="$INSTALL_DIR/workspace"
USB_LOG_DIR="$ROOT_DIR/logs"
CHAT_TEMPLATE_FILE="Qwen3-4B-Instruct-2507.jinja"
CHAT_TEMPLATE_SOURCE="$ROOT_DIR/assets/templates/$CHAT_TEMPLATE_FILE"
CHAT_TEMPLATE_TARGET="$TEMPLATE_DIR/$CHAT_TEMPLATE_FILE"
TECHKIT_DIR="${ROOT_DIR:h}/TechKit"
DRAFT_MODEL_FILE="qwen3-0.6b-q8_0.gguf"
DRAFT_MODEL_SOURCE="$ROOT_DIR/models/$DRAFT_MODEL_FILE"
DRAFT_MODEL_TARGET=""
SERVER_URL="http://127.0.0.1:1234/v1"
LOCAL_API_KEY="local"
APPROVAL_MODE="${QWEN_APPROVAL_MODE:-auto-edit}"
DEFAULT_SYSTEM_PROMPT="You are a local computer technician agent running inside Qwen Code on a customer machine. Tools: run_shell_command, read_file, edit. PRIME RULE: for diagnostics and repairs, prefer running the vetted TechKit scripts listed in QWEN.md over writing new code. Match the user's complaint to a script, run it with run_shell_command, then interpret the output: lead with any [!] findings, then a short diagnosis and the single next step. Act immediately with a tool call; never reply with a prose plan, and do not say you will run something unless you call the tool now. Keep replies under 150 words: exact counts, paths, and errors only; never restate full tool output the user already saw. Destructive TechKit scripts dry-run by default: run the dry-run first, show what would change, get explicit user confirmation, then re-run with the force flag. Never disable or delete administrator accounts; the scripts refuse this and you must not work around them. If no TechKit script fits the task, write a custom script to a file with the edit tool and reply with one sentence plus the file path; never paste a full script into chat. Use zsh-compatible commands on macOS and absolute paths. If an action needs root and the shell is not elevated, say so and give the exact sudo command instead of pretending it ran. When a job wraps up, offer a short ticket summary (problem, findings, actions, result)."
SYSTEM_PROMPT="${QWEN_SYSTEM_PROMPT:-$DEFAULT_SYSTEM_PROMPT}"
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
HOST_NAME="$(scutil --get ComputerName 2>/dev/null || hostname || printf 'mac')"
SAFE_HOST_NAME="$(printf '%s' "$HOST_NAME" | tr -c 'A-Za-z0-9_.-' '_')"
RUN_LOG="$USB_LOG_DIR/${SAFE_HOST_NAME}-macos-$RUN_STAMP.log"

log() {
  local message="$1"
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message" | tee -a "$RUN_LOG"
}

copy_server_log_to_usb() {
  if [[ -f "$LOG_DIR/llama-server.log" ]]; then
    cp "$LOG_DIR/llama-server.log" "$USB_LOG_DIR/${SAFE_HOST_NAME}-macos-llama-server-$RUN_STAMP.log" 2>/dev/null || true
  fi
  if [[ -d "$LOG_DIR/openai" ]]; then
    local openai_copy="$USB_LOG_DIR/${SAFE_HOST_NAME}-macos-openai-$RUN_STAMP"
    rm -rf "$openai_copy" 2>/dev/null || true
    mkdir -p "$openai_copy" 2>/dev/null || true
    cp -R "$LOG_DIR/openai/." "$openai_copy/" 2>/dev/null || true
  fi
}

fail() {
  copy_server_log_to_usb
  printf '\nERROR: %s\n' "$1" >&2
  printf 'Log: %s\n' "$RUN_LOG" >&2
  printf 'Press Return to close this window.\n' >&2
  read -r _ || true
  exit 1
}

copy_if_needed() {
  local source="$1"
  local target="$2"
  if [[ ! -f "$source" ]]; then
    fail "Missing required file: $source"
  fi

  if [[ ! -f "$target" || "$(stat -f '%z' "$source")" != "$(stat -f '%z' "$target" 2>/dev/null || printf 0)" ]]; then
    log "Copying $(basename "$source") to $target"
    cp "$source" "$target"
  else
    log "Using existing $(basename "$target")"
  fi
}

find_archive() {
  local pattern="$1"
  local family="$2"
  local archive
  archive="$(find "$ROOT_DIR/assets/$family" -maxdepth 1 -type f -name "$pattern" | head -n 1)"
  if [[ -z "$archive" ]]; then
    fail "Missing $family archive matching $pattern in $ROOT_DIR/assets/$family"
  fi
  printf '%s\n' "$archive"
}

select_model() {
  local requested="${QWEN_MODEL_SIZE:-auto}"
  requested="${requested:l}"
  case "$requested" in
    auto|4b|qwen3|qwen3-4b|qwen3-4b-instruct-2507)
      MODEL_FILE="qwen3-4b-instruct-2507-q4_k_m.gguf"
      MODEL_ID="local/qwen3-4b-instruct-2507-q4_k_m"
      MODEL_DISPLAY_NAME="Qwen3-4B Instruct 2507 Q4_K_M"
      DEFAULT_CONTEXT_SIZE="32768"
      DEFAULT_OUTPUT_TOKENS="4096"
      ;;
    3b|7b)
      log "QWEN_MODEL_SIZE=$requested is from the legacy build; selecting Qwen3 4B instead."
      MODEL_FILE="qwen3-4b-instruct-2507-q4_k_m.gguf"
      MODEL_ID="local/qwen3-4b-instruct-2507-q4_k_m"
      MODEL_DISPLAY_NAME="Qwen3-4B Instruct 2507 Q4_K_M"
      DEFAULT_CONTEXT_SIZE="32768"
      DEFAULT_OUTPUT_TOKENS="4096"
      ;;
    *)
      fail "Unsupported QWEN_MODEL_SIZE value: $requested. Use auto or 4b."
      ;;
  esac

  CONTEXT_SIZE="${QWEN_CONTEXT_SIZE:-$DEFAULT_CONTEXT_SIZE}"
  OUTPUT_TOKENS="${QWEN_MAX_OUTPUT_TOKENS:-$DEFAULT_OUTPUT_TOKENS}"
  MODEL_SOURCE="$ROOT_DIR/models/$MODEL_FILE"
  MODEL_TARGET="$MODEL_DIR/$MODEL_FILE"

  log "Selected model: $MODEL_DISPLAY_NAME"
  log "Model file: $MODEL_FILE"
  log "Context size: $CONTEXT_SIZE tokens"
  log "Max output tokens: $OUTPUT_TOKENS"
}

extract_qwen_code() {
  local archive="$1"
  if [[ -x "$QWEN_CODE_DIR/bin/qwen" ]]; then
    log "Using existing Qwen Code install: $QWEN_CODE_DIR"
    return 0
  fi

  local temp_dir="$INSTALL_DIR/tmp/qwen-code"
  rm -rf "$temp_dir" "$QWEN_CODE_DIR"
  mkdir -p "$temp_dir" "$QWEN_CODE_DIR"
  log "Extracting Qwen Code from $(basename "$archive")"
  tar -xzf "$archive" -C "$temp_dir"

  local qwen_bin
  qwen_bin="$(find "$temp_dir" -type f -path '*/bin/qwen' -perm -111 | head -n 1)"
  if [[ -z "$qwen_bin" ]]; then
    fail "Could not find qwen executable inside $archive"
  fi

  local package_dir
  package_dir="$(dirname "$(dirname "$qwen_bin")")"
  cp -R "$package_dir"/. "$QWEN_CODE_DIR"/
  chmod +x "$QWEN_CODE_DIR/bin/qwen" "$QWEN_CODE_DIR/node/bin/node" 2>/dev/null || true
}

extract_llama() {
  local archive="$1"
  if [[ -x "$LLAMA_DIR/llama-server" ]]; then
    log "Using existing llama.cpp install: $LLAMA_DIR"
    return 0
  fi

  local temp_dir="$INSTALL_DIR/tmp/llama"
  rm -rf "$temp_dir" "$LLAMA_DIR"
  mkdir -p "$temp_dir" "$LLAMA_DIR"
  log "Extracting llama.cpp from $(basename "$archive")"
  tar -xzf "$archive" -C "$temp_dir"

  local binary
  binary="$(find "$temp_dir" -type f -perm -111 -name 'llama-server' | head -n 1)"
  if [[ -z "$binary" ]]; then
    fail "Could not find llama-server binary inside $archive"
  fi

  local package_dir
  package_dir="$(dirname "$binary")"
  cp -R "$package_dir"/. "$LLAMA_DIR"/
  chmod +x "$LLAMA_DIR/llama-server" 2>/dev/null || true
}

server_is_ready() {
  curl -fsS "http://127.0.0.1:1234/v1/models" 2>/dev/null | grep -q "$MODEL_ID"
}

port_responds() {
  curl -fsS "http://127.0.0.1:1234/v1/models" >/dev/null 2>&1
}

cleanup_legacy_install() {
  if [[ ! -d "$LEGACY_INSTALL_DIR" ]]; then
    return 0
  fi

  log "Removing previous Codex-based Qwen Coder install: $LEGACY_INSTALL_DIR"
  local legacy_pid_file="$LEGACY_INSTALL_DIR/run/llama-server.pid"
  if [[ -f "$legacy_pid_file" ]]; then
    local old_pid
    old_pid="$(cat "$legacy_pid_file" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      kill "$old_pid" 2>/dev/null || true
      sleep 1
    fi
  fi

  if command -v pgrep >/dev/null 2>&1; then
    pgrep -f "$LEGACY_INSTALL_DIR/llama.cpp/llama-server" 2>/dev/null | while read -r pid; do
      [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
    done
  fi

  rm -rf "$LEGACY_INSTALL_DIR"
}

start_server() {
  local pid_file="$RUN_DIR/llama-server.pid"
  if [[ -f "$pid_file" ]]; then
    local old_pid
    old_pid="$(cat "$pid_file" 2>/dev/null || true)"
    if [[ -n "$old_pid" ]] && kill -0 "$old_pid" 2>/dev/null; then
      log "Stopping previous toolkit llama-server process $old_pid"
      kill "$old_pid" 2>/dev/null || true
      sleep 1
    fi
  fi

  if port_responds; then
    curl -fsS "http://127.0.0.1:1234/v1/models" >> "$RUN_LOG" 2>&1 || true
    fail "Port 1234 is already serving a model from another process. Stop that server and run this launcher again."
  fi

  log "Starting llama-server on 127.0.0.1:1234"
  log "Server log: $LOG_DIR/llama-server.log"
  log "Chat template: $CHAT_TEMPLATE_TARGET"
  local gpu_args=()
  if [[ "$(uname -m)" == "arm64" ]]; then
    gpu_args=(-ngl 999)
    log "llama-server Metal GPU offload: enabled"
  fi

  # Speed: reuse prompt-cache chunks across requests; flash attention + q8_0 KV cache
  # roughly halves KV memory at 32K context (matters most on 8 GB machines).
  local speed_args=(--cache-reuse 256 -fa on --cache-type-k q8_0 --cache-type-v q8_0)

  # Speculative decoding: benchmarked SLOWER than plain decoding for this model pairing
  # (draft-simple 0.76x, ngram-simple 0.44x on repetition) - off by default.
  # QWEN_SPEC=draft|ngram-simple|... re-enables it for experiments.
  local spec_args=()
  case "${QWEN_SPEC:-off}" in
    off|none|0)
      log "Speculative decoding: off" ;;
    draft)
      if [[ -n "$DRAFT_MODEL_TARGET" && -f "$DRAFT_MODEL_TARGET" ]]; then
        spec_args=(--spec-type draft-simple --model-draft "$DRAFT_MODEL_TARGET" \
                   --spec-draft-n-max 8 --spec-draft-n-min 2 --spec-draft-p-min 0.75 \
                   -ctkd q8_0 -ctvd q8_0)
        if [[ "$(uname -m)" == "arm64" ]]; then spec_args+=(-ngld 999); fi
        log "Speculative decoding: draft-simple with $DRAFT_MODEL_FILE (experimental)"
      else
        log "QWEN_SPEC=draft but $DRAFT_MODEL_FILE missing; speculative decoding off"
      fi
      ;;
    *)
      spec_args=(--spec-type "${QWEN_SPEC}")
      log "Speculative decoding: ${QWEN_SPEC} (experimental)"
      ;;
  esac

  nohup "$LLAMA_DIR/llama-server" \
    -m "$MODEL_TARGET" \
    --host 127.0.0.1 \
    --port 1234 \
    --alias "$MODEL_ID" \
    -c "$CONTEXT_SIZE" \
    --parallel 1 \
    --jinja \
    --chat-template-file "$CHAT_TEMPLATE_TARGET" \
    --reasoning off \
    "${speed_args[@]}" \
    "${spec_args[@]}" \
    "${gpu_args[@]}" \
    > "$LOG_DIR/llama-server.log" 2>&1 &
  printf '%s\n' "$!" > "$pid_file"

  for _ in {1..60}; do
    if server_is_ready; then
      log "llama-server is ready"
      curl -fsS "http://127.0.0.1:1234/v1/models" >> "$RUN_LOG" 2>&1 || true
      return 0
    fi
    sleep 1
  done

  fail "llama-server did not become ready. See $LOG_DIR/llama-server.log"
}

write_qwen_workspace_config() {
  mkdir -p "$WORK_ROOT/.qwen" "$QWEN_HOME_DIR" "$QWEN_RUNTIME_DIR" "$LOG_DIR/openai"

  cat > "$WORK_ROOT/.qwen/settings.json" <<EOF
{
  "modelProviders": {
    "openai": [
      {
        "id": "$MODEL_ID",
        "name": "$MODEL_DISPLAY_NAME",
        "description": "Local llama.cpp server started by Qwen Coder Tech Agent",
        "envKey": "OPENAI_API_KEY",
        "baseUrl": "$SERVER_URL",
        "generationConfig": {
          "timeout": 600000,
          "maxRetries": 0,
          "contextWindowSize": $CONTEXT_SIZE,
          "splitToolMedia": true,
          "samplingParams": {
            "temperature": 0.2,
            "top_p": 0.9,
            "max_tokens": $OUTPUT_TOKENS
          }
        }
      }
    ]
  },
  "env": {
    "OPENAI_API_KEY": "$LOCAL_API_KEY",
    "OPENAI_BASE_URL": "$SERVER_URL",
    "OPENAI_MODEL": "$MODEL_ID"
  },
  "security": {
    "auth": {
      "selectedType": "openai"
    }
  },
  "model": {
    "name": "$MODEL_ID",
    "skipStartupContext": true,
    "enableOpenAILogging": true,
    "openAILoggingDir": "$LOG_DIR/openai"
  },
  "tools": {
    "approvalMode": "$APPROVAL_MODE",
    "sandbox": false,
    "useRipgrep": true,
    "truncateToolOutputThreshold": 50000,
    "truncateToolOutputLines": 2000
  },
  "permissions": {
    "allow": ["Read", "Edit", "Write", "Grep", "Glob", "ListFiles"]
  },
  "context": {
    "includeDirectories": ["$REAL_HOME", "/Applications", "/Library", "/Volumes"],
    "loadFromIncludeDirectories": false,
    "fileFiltering": {
      "respectGitIgnore": true,
      "respectQwenIgnore": true,
      "enableFuzzySearch": false
    }
  },
  "general": {
    "checkpointing": {
      "enabled": true
    }
  },
  "memory": {
    "enableManagedAutoMemory": false,
    "enableManagedAutoDream": false,
    "enableAutoSkill": false
  },
  "privacy": {
    "usageStatisticsEnabled": false
  },
  "telemetry": {
    "enabled": false
  }
}
EOF

  local catalog_md="$TECHKIT_DIR/catalog-macos.md"
  {
    printf '# Qwen Coder Tech Agent - technician workspace\n\n'
    printf 'Follow the technician system prompt. Prefer TechKit scripts below over writing new code.\n'
    printf 'TechKit library (USB): %s\n' "$TECHKIT_DIR"
    printf 'Evidence bundles land in: %s/collections\n\n' "$TECHKIT_DIR"
    if [[ -f "$catalog_md" ]]; then
      sed -e "s|__TECHKIT__|$TECHKIT_DIR|g" -e "s|__CATALOG__|$TECHKIT_DIR/catalog.json|g" "$catalog_md"
    else
      printf '(TechKit catalog not found on USB - fall back to plain shell commands.)\n'
    fi
  } > "$WORK_ROOT/QWEN.md"

  log "Wrote Qwen Code project settings: $WORK_ROOT/.qwen/settings.json"
  log "Wrote Qwen instructions with TechKit catalog: $WORK_ROOT/QWEN.md"
}

validate_approval_mode() {
  case "$APPROVAL_MODE" in
    plan|default|auto-edit|auto|yolo) ;;
    *) fail "Unsupported QWEN_APPROVAL_MODE value: $APPROVAL_MODE. Use plan, default, auto-edit, auto, or yolo." ;;
  esac
}

main() {
  mkdir -p "$USB_LOG_DIR"
  log "Starting Qwen Coder Tech Agent launcher"
  log "USB root: $ROOT_DIR"
  log "Install dir: $INSTALL_DIR"
  log "Qwen Code home: $QWEN_HOME_DIR"
  log "Qwen workspace: $WORK_ROOT"
  log "Approval mode: $APPROVAL_MODE"

  validate_approval_mode
  select_model

  local machine_arch
  machine_arch="$(uname -m)"
  log "Detected Mac architecture: $machine_arch"

  local qwen_archive
  local llama_archive
  case "$machine_arch" in
    arm64)
      qwen_archive="$(find_archive 'qwen-code-darwin-arm64.tar.gz' 'qwen-code')"
      llama_archive="$(find_archive 'llama-*-bin-macos-arm64.tar.gz' 'llama.cpp')"
      ;;
    x86_64)
      qwen_archive="$(find_archive 'qwen-code-darwin-x64.tar.gz' 'qwen-code')"
      llama_archive="$(find_archive 'llama-*-bin-macos-x64.tar.gz' 'llama.cpp')"
      ;;
    *)
      fail "Unsupported Mac architecture: $machine_arch"
      ;;
  esac

  mkdir -p "$QWEN_CODE_DIR" "$QWEN_HOME_DIR" "$QWEN_RUNTIME_DIR" "$LLAMA_DIR" "$MODEL_DIR" "$TEMPLATE_DIR" "$LOG_DIR" "$RUN_DIR" "$WORK_ROOT" "$INSTALL_DIR/tmp"
  cleanup_legacy_install
  copy_if_needed "$MODEL_SOURCE" "$MODEL_TARGET"
  if [[ "${QWEN_SPEC:-off}" == "draft" && -f "$DRAFT_MODEL_SOURCE" ]]; then
    DRAFT_MODEL_TARGET="$MODEL_DIR/$DRAFT_MODEL_FILE"
    copy_if_needed "$DRAFT_MODEL_SOURCE" "$DRAFT_MODEL_TARGET"
  fi
  copy_if_needed "$CHAT_TEMPLATE_SOURCE" "$CHAT_TEMPLATE_TARGET"
  extract_qwen_code "$qwen_archive"
  extract_llama "$llama_archive"
  xattr -dr com.apple.quarantine "$INSTALL_DIR" 2>/dev/null || true
  write_qwen_workspace_config
  start_server
  # Copy server log to USB now, not only on exit, so evidence survives a yanked drive
  copy_server_log_to_usb

  export QWEN_HOME="$QWEN_HOME_DIR"
  export QWEN_RUNTIME_DIR="$QWEN_RUNTIME_DIR"
  export QWEN_SANDBOX=false
  export QWEN_TELEMETRY_ENABLED=false
  export QWEN_CODE_TOOL_CALL_STYLE=qwen-coder
  export QWEN_CODE_MAX_OUTPUT_TOKENS="$OUTPUT_TOKENS"
  export QWEN_CODE_SUPPRESS_YOLO_WARNING=1
  export LOCAL_QWEN_API_KEY="$LOCAL_API_KEY"
  export OPENAI_API_KEY="$LOCAL_API_KEY"
  export OPENAI_BASE_URL="$SERVER_URL"
  export OPENAI_MODEL="$MODEL_ID"

  cd "$WORK_ROOT"
  log "Changed shell working directory to Qwen workspace: $WORK_ROOT"
  "$QWEN_CODE_DIR/bin/qwen" --version >> "$RUN_LOG" 2>&1 || true

  printf '\nQwen Coder local server is ready at %s\n' "$SERVER_URL"
  printf 'Launching Qwen Code with %s...\n\n' "$MODEL_DISPLAY_NAME"
  log "Launching Qwen Code: $QWEN_CODE_DIR/bin/qwen --bare -e none --auth-type openai --model $MODEL_ID --approval-mode $APPROVAL_MODE --system-prompt <technician>"
  log "Included directories: $REAL_HOME, /Applications, /Library, /Volumes"
  log "OpenAI API logs will be copied to USB on exit"

  set +e
  "$QWEN_CODE_DIR/bin/qwen" \
    --bare \
    -e none \
    --auth-type openai \
    --model "$MODEL_ID" \
    --openai-api-key "$LOCAL_API_KEY" \
    --openai-base-url "$SERVER_URL" \
    --openai-logging \
    --openai-logging-dir "$LOG_DIR/openai" \
    --approval-mode "$APPROVAL_MODE" \
    --core-tools run_shell_command \
    --core-tools read_file \
    --core-tools edit \
    --exclude-tools notebook_edit \
    --system-prompt "$SYSTEM_PROMPT" \
    --include-directories "$REAL_HOME,/Applications,/Library,/Volumes"
  qwen_status="$?"
  set -e

  copy_server_log_to_usb
  log "Qwen Code exited with status $qwen_status"
  if [[ "$qwen_status" != "0" ]]; then
    printf '\nQwen Code exited with status %s.\n' "$qwen_status" >&2
    printf 'Launcher log: %s\n' "$RUN_LOG" >&2
    printf '\nPress Return to close this window.\n' >&2
    read -r _ || true
  fi
}

main "$@"
