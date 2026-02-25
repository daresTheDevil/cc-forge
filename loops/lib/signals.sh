#!/usr/bin/env bash
# ~/.claude/loops/lib/signals.sh
# CC-Forge shared signal parsing, locking, archiving, and utility functions.
# Source this file at the top of forge-loop.sh and build.sh.
#
# Depends on: jq, dasel

# ---------------------------------------------------------------------------
# Logging (all output goes to stderr — keeps stdout clean for piping)
# ---------------------------------------------------------------------------
log_info()  { printf '[%s] INFO  %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
log_warn()  { printf '[%s] WARN  %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
log_error() { printf '[%s] ERROR %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }

# ---------------------------------------------------------------------------
# JSON signal parsing
# All functions read from a JSON file path (not stdin) for reliability.
# ---------------------------------------------------------------------------

# Extract .session_id from the CLI output envelope (used for --resume)
parse_session_id() {
  local json_file="$1"
  jq -r '.session_id // empty' "$json_file" 2>/dev/null
}

# Extract .structured_output.status
parse_status() {
  local json_file="$1"
  jq -r '.structured_output.status // empty' "$json_file" 2>/dev/null
}

# Extract .structured_output.delta (forge loop only)
parse_delta() {
  local json_file="$1"
  jq -r '.structured_output.delta // 0' "$json_file" 2>/dev/null
}

# Generic field extractor: parse_field <file> <jq_path> [default]
parse_field() {
  local json_file="$1"
  local path="$2"
  local default="${3:-}"
  jq -r "${path} // empty" "$json_file" 2>/dev/null || echo "$default"
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

# Fail fast if Claude output is not valid JSON
assert_json_valid() {
  local json_file="$1"
  if ! jq empty "$json_file" >/dev/null 2>&1; then
    log_error "Claude output is not valid JSON: $json_file"
    log_error "Content (first 500 chars): $(head -c 500 "$json_file" 2>/dev/null)"
    return 1
  fi
  return 0
}

# Fail fast if .structured_output is missing or null
# This catches: --json-schema enforcement failure, Claude error responses
assert_structured_output() {
  local json_file="$1"
  local structured
  structured=$(jq -r '.structured_output // empty' "$json_file" 2>/dev/null)
  if [ -z "$structured" ] || [ "$structured" = "null" ]; then
    log_error "Claude output missing .structured_output — --json-schema enforcement may have failed"
    log_error "Raw output (first 500 chars): $(head -c 500 "$json_file" 2>/dev/null)"
    return 1
  fi
  return 0
}

# ---------------------------------------------------------------------------
# Lockfile management (PID-aware — detects stale locks from crashed processes)
# ---------------------------------------------------------------------------

acquire_lock() {
  local lockfile="$1"
  local lockdir
  lockdir=$(dirname "$lockfile")
  mkdir -p "$lockdir"

  if [ -f "$lockfile" ]; then
    local pid
    pid=$(cat "$lockfile" 2>/dev/null || echo "")
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      log_error "Another forge process is already running (PID: $pid)"
      log_error "Lock file: $lockfile"
      log_error "If this is stale, remove it manually: rm $lockfile"
      return 1
    else
      log_warn "Stale lockfile found (PID $pid no longer running) — cleaning up"
      rm -f "$lockfile"
    fi
  fi

  echo $$ > "$lockfile"
  log_info "Lock acquired: $lockfile (PID: $$)"
  return 0
}

release_lock() {
  local lockfile="$1"
  if [ -f "$lockfile" ]; then
    rm -f "$lockfile"
    log_info "Lock released: $lockfile"
  fi
}

# ---------------------------------------------------------------------------
# Run archiving — writes per-run JSON and appends to JSONL time-series
# ---------------------------------------------------------------------------

archive_run() {
  # archive_run <run_json_data_string> <history_dir> <metrics_jsonl_file>
  local run_data="$1"
  local history_dir="$2"
  local metrics_file="$3"
  local timestamp
  timestamp=$(date '+%Y-%m-%dT%H%M%S')
  local archive_file="${history_dir}/forge-${timestamp}.json"

  mkdir -p "$history_dir"
  mkdir -p "$(dirname "$metrics_file")"

  # Per-run archive (pretty-printed for readability)
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$run_data" | jq '.' > "$archive_file" 2>/dev/null || printf '%s' "$run_data" > "$archive_file"
  else
    printf '%s' "$run_data" > "$archive_file"
  fi
  log_info "Run archived: $archive_file"

  # Append to JSONL time-series (one line per event — OTel-compatible span format)
  # jq -c ensures single-line compact JSON for JSONL
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$run_data" | jq -c '.' >> "$metrics_file" 2>/dev/null || printf '%s\n' "$run_data" >> "$metrics_file"
  else
    printf '%s\n' "$run_data" >> "$metrics_file"
  fi
  log_info "Metrics appended to JSONL: $metrics_file"
}

# ---------------------------------------------------------------------------
# Progress tracking — human-readable session log
# ---------------------------------------------------------------------------

update_progress() {
  # update_progress <progress_file> <message> [session_id]
  local progress_file="$1"
  local message="$2"
  local session_id="${3:-}"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  {
    printf '\n## %s\n' "$timestamp"
    printf '%s\n' "$message"
    [ -n "$session_id" ] && printf 'Session: %s\n' "$session_id"
  } >> "$progress_file"
}

# ---------------------------------------------------------------------------
# Critical notifications — Slack webhook (silent no-op if FORGE_SLACK_WEBHOOK unset)
# Only fires on HALT-grade findings
# ---------------------------------------------------------------------------

notify_critical() {
  # notify_critical <message> [grade]
  local message="$1"
  local grade="${2:-HALT}"

  # Only send for HALT-grade findings
  [ "$grade" != "HALT" ] && return 0

  # Silently skip if webhook not configured
  local webhook="${FORGE_SLACK_WEBHOOK:-}"
  [ -z "$webhook" ] && return 0

  if ! command -v curl >/dev/null 2>&1; then
    log_warn "notify_critical: curl not found — Slack notification skipped"
    return 0
  fi

  local payload
  payload=$(printf '{"text":"🚨 *CC-Forge [HALT]*\\n%s"}' "$message")

  curl -s -X POST \
    -H 'Content-type: application/json' \
    --data "$payload" \
    "$webhook" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------------------
# TOML config cascade: project.toml → workspace.toml → forge.toml → default
# Uses dasel (hard dependency — install: brew install dasel)
# ---------------------------------------------------------------------------

read_config() {
  # read_config <toml_key> [default]
  # Key format follows dasel selectors: e.g., "workflow.improve.improvement_threshold"
  local key="$1"
  local default="${2:-}"
  local workspace_toml="${WORKSPACE_TOML:-}"
  local value=""

  # 1. Project level
  if [ -z "$value" ] && [ -f ".claude/forge/project.toml" ]; then
    value=$(dasel -f ".claude/forge/project.toml" "$key" 2>/dev/null || echo "")
  fi

  # 2. Workspace level
  if [ -z "$value" ] && [ -n "$workspace_toml" ] && [ -f "$workspace_toml" ]; then
    value=$(dasel -f "$workspace_toml" "$key" 2>/dev/null || echo "")
  fi

  # 3. Global forge.toml
  if [ -z "$value" ] && [ -f "$HOME/.claude/forge/forge.toml" ]; then
    value=$(dasel -f "$HOME/.claude/forge/forge.toml" "$key" 2>/dev/null || echo "")
  fi

  # 4. Hardcoded default
  echo "${value:-$default}"
}
