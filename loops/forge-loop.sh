#!/usr/bin/env bash
# ~/.claude/loops/forge-loop.sh
# CC-Forge: Forge Loop controller
#
# Runs the continuous improvement loop headlessly via Claude CLI.
# Claude executes single iterations; this script controls looping logic.
#
# Usage:
#   forge-loop.sh [--scope <path>] [--max-iter N] [--threshold F] [--workspace-toml <path>]
#   forge-loop.sh src/                          # improve everything in src/
#   forge-loop.sh --scope src/api --max-iter 5  # explicit flags
#
# Exit codes:
#   0 = complete (delta below threshold or queue exhausted)
#   1 = error (Claude failed, JSON invalid, or dependency missing)
#   2 = blocked (human input required — see JSONL for details)
#
# Requires: jq, dasel, claude CLI, bash 4.0+ (brew install bash on macOS)

set -euo pipefail

# Resolve lib directory relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${SCRIPT_DIR}/lib"

# shellcheck source=lib/signals.sh
source "${LIB_DIR}/signals.sh"

# ---------------------------------------------------------------------------
# Dependency checks
# ---------------------------------------------------------------------------
for dep in jq dasel claude; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    printf 'ERROR: "%s" is required but not installed.\n' "$dep" >&2
    printf 'Run: ~/.claude/forge/install.sh --global\n' >&2
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
SCOPE="."
MAX_ITER=10
THRESHOLD=""
WORKSPACE_TOML=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scope)          SCOPE="$2";          shift 2 ;;
    --max-iter)       MAX_ITER="$2";       shift 2 ;;
    --threshold)      THRESHOLD="$2";      shift 2 ;;
    --workspace-toml) WORKSPACE_TOML="$2"; shift 2 ;;
    -*)
      printf 'Unknown flag: %s\n' "$1" >&2
      printf 'Usage: forge-loop.sh [--scope PATH] [--max-iter N] [--threshold F]\n' >&2
      exit 1
      ;;
    *)
      # Positional arg = scope (shorthand)
      SCOPE="$1"
      shift
      ;;
  esac
done

export WORKSPACE_TOML

# ---------------------------------------------------------------------------
# Config cascade (read threshold if not provided via CLI flag)
# ---------------------------------------------------------------------------
if [ -z "$THRESHOLD" ]; then
  THRESHOLD=$(read_config "workflow.improve.improvement_threshold" "0.05")
fi

# Validate threshold is a number
if ! printf '%s' "$THRESHOLD" | grep -qE '^[0-9]+(\.[0-9]+)?$'; then
  log_error "Invalid threshold: '$THRESHOLD' — must be a decimal number (e.g., 0.05)"
  exit 1
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCHEMA_FILE="${LIB_DIR}/improve-signal-schema.json"
LOCKFILE=".forge/forge-loop.lock"
HISTORY_DIR=".forge/history"
METRICS_FILE=".forge/metrics/forge-metrics.jsonl"
PROGRESS_FILE="claude-progress.txt"

if [ ! -f "$SCHEMA_FILE" ]; then
  log_error "Schema file not found: $SCHEMA_FILE"
  log_error "Reinstall CC-Forge: ~/.claude/forge/install.sh --global"
  exit 1
fi

TEMP_OUTPUT=$(mktemp /tmp/forge-loop-output.XXXXXX.json)

cleanup() {
  rm -f "$TEMP_OUTPUT"
  release_lock "$LOCKFILE" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Acquire lock (prevents concurrent runs)
# ---------------------------------------------------------------------------
acquire_lock "$LOCKFILE" || exit 1

# ---------------------------------------------------------------------------
# Build the iteration prompt template
# The loop injects scope, iteration number, and prior context each invocation.
# ---------------------------------------------------------------------------
IMPROVE_CMD_PATH="${HOME}/.claude/commands/forge--improve.md"
if [ ! -f "$IMPROVE_CMD_PATH" ]; then
  log_error "Improve command not found: $IMPROVE_CMD_PATH"
  log_error "Reinstall CC-Forge: ~/.claude/forge/install.sh --global"
  exit 1
fi

# ---------------------------------------------------------------------------
# Run the loop
# ---------------------------------------------------------------------------
SESSION_ID=""
ITERATION=0
FINAL_STATUS="complete"
DELTA="0"
SUMMARY=""
RUN_START=$(date '+%Y-%m-%dT%H:%M:%SZ')
TRACE_ID="forge-loop-$(date '+%Y%m%d-%H%M%S')"
ALL_IMPROVEMENTS=()
BASELINE_METRICS="null"
FINAL_METRICS="null"

log_info "Forge Loop starting | Scope: ${SCOPE} | MaxIter: ${MAX_ITER} | Threshold: ${THRESHOLD}"

# Update state.json phase to 'improving' if it exists
if [ -f ".forge/state.json" ] && command -v jq >/dev/null 2>&1; then
  TMP_STATE=$(mktemp)
  jq '.phase = "improving"' ".forge/state.json" > "$TMP_STATE" && mv "$TMP_STATE" ".forge/state.json"
fi

while true; do
  ITERATION=$((ITERATION + 1))

  if [ "$ITERATION" -gt "$MAX_ITER" ]; then
    log_info "Max iterations (${MAX_ITER}) reached — stopping"
    FINAL_STATUS="complete"
    break
  fi

  log_info "─── Iteration ${ITERATION}/${MAX_ITER} ───────────────────────────────"

  # Build the prompt for this iteration
  PROMPT=$(cat <<EOF
You are executing iteration ${ITERATION} of the CC-Forge Forge Loop.

Scope: ${SCOPE}
Iteration: ${ITERATION}
Max iterations: ${MAX_ITER}
Improvement threshold: ${THRESHOLD}
Timestamp: $(date '+%Y-%m-%dT%H:%M:%SZ')

Read the instructions in ~/.claude/commands/forge--improve.md and execute ONE improvement iteration for the scope above.

You MUST output ONLY a valid JSON object. No markdown, no explanation, no other text.
The output must conform to the improve-signal-schema.json contract.
EOF
)

  # Build --resume flag from previous iteration's session ID
  RESUME_FLAG=()
  if [ -n "$SESSION_ID" ]; then
    RESUME_FLAG=(--resume "$SESSION_ID")
  fi

  # Invoke Claude for one iteration
  # shellcheck disable=SC2086
  if ! claude \
    -p "$PROMPT" \
    --output-format json \
    --json-schema "$(cat "$SCHEMA_FILE")" \
    --allowedTools "Read,Edit,Bash,Glob,Grep" \
    "${RESUME_FLAG[@]}" \
    > "$TEMP_OUTPUT" 2>/dev/null; then
    log_error "Claude CLI exited non-zero on iteration ${ITERATION}"
    FINAL_STATUS="error"
    break
  fi

  # Validate the output
  if ! assert_json_valid "$TEMP_OUTPUT"; then
    FINAL_STATUS="error"
    break
  fi

  if ! assert_structured_output "$TEMP_OUTPUT"; then
    FINAL_STATUS="error"
    break
  fi

  # Extract signal fields
  SESSION_ID=$(parse_session_id "$TEMP_OUTPUT")
  STATUS=$(parse_status "$TEMP_OUTPUT")
  DELTA=$(parse_delta "$TEMP_OUTPUT")
  SUMMARY=$(parse_field "$TEMP_OUTPUT" '.structured_output.summary' "(no summary)")
  NEXT_FOCUS=$(parse_field "$TEMP_OUTPUT" '.structured_output.next_focus' "")

  # Capture metrics (baseline on first iteration, final on every iteration)
  CURRENT_METRICS=$(jq '.structured_output.metrics // null' "$TEMP_OUTPUT" 2>/dev/null || echo "null")
  if [ "$ITERATION" -eq 1 ]; then
    BASELINE_METRICS="$CURRENT_METRICS"
  fi
  FINAL_METRICS="$CURRENT_METRICS"

  # Accumulate completed improvements
  while IFS= read -r item; do
    [ -n "$item" ] && ALL_IMPROVEMENTS+=("$item")
  done < <(jq -r '.structured_output.completed[]?' "$TEMP_OUTPUT" 2>/dev/null || true)

  log_info "Status: ${STATUS} | Delta: ${DELTA} | ${SUMMARY}"
  [ -n "$NEXT_FOCUS" ] && log_info "Next focus: ${NEXT_FOCUS}"

  # Branch on status
  case "$STATUS" in
    "loop")
      # Check if delta actually warrants another iteration
      if command -v bc >/dev/null 2>&1; then
        if (( $(echo "$DELTA < $THRESHOLD" | bc -l) )); then
          log_info "Delta (${DELTA}) is below threshold (${THRESHOLD}) despite 'loop' signal — stopping"
          FINAL_STATUS="complete"
          break
        fi
      fi
      log_info "Continuing (delta ${DELTA} >= threshold ${THRESHOLD})"
      ;;
    "complete")
      log_info "Claude signaled completion"
      FINAL_STATUS="complete"
      break
      ;;
    "error")
      log_error "Claude reported error: ${SUMMARY}"
      FINAL_STATUS="error"
      break
      ;;
    "blocked")
      BLOCKER_COUNT=$(jq '.structured_output.blockers | length' "$TEMP_OUTPUT" 2>/dev/null || echo "unknown")
      log_warn "Forge loop blocked — ${BLOCKER_COUNT} blocker(s) require human input"
      log_warn "Summary: ${SUMMARY}"
      log_warn "Session ID for resume: ${SESSION_ID}"
      FINAL_STATUS="blocked"
      break
      ;;
    *)
      log_error "Unknown status signal: '${STATUS}'"
      FINAL_STATUS="error"
      break
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Build improvements JSON array
# ---------------------------------------------------------------------------
IMPROVEMENTS_JSON="[]"
if [ ${#ALL_IMPROVEMENTS[@]} -gt 0 ]; then
  IMPROVEMENTS_JSON=$(printf '%s\n' "${ALL_IMPROVEMENTS[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
fi

# ---------------------------------------------------------------------------
# Archive the run (per-run JSON + JSONL time-series)
# ---------------------------------------------------------------------------
RUN_ARCHIVE=$(jq -n \
  --arg timestamp "$RUN_START" \
  --arg trace_id "$TRACE_ID" \
  --arg span_type "forge_loop_run" \
  --arg session_id "$SESSION_ID" \
  --arg scope "$SCOPE" \
  --argjson iterations "$ITERATION" \
  --arg final_status "$FINAL_STATUS" \
  --argjson metrics_start "$BASELINE_METRICS" \
  --argjson metrics_end "$FINAL_METRICS" \
  --arg delta "$DELTA" \
  --argjson improvements "$IMPROVEMENTS_JSON" \
  '{
    timestamp: $timestamp,
    trace_id: $trace_id,
    span_type: $span_type,
    session_id: $session_id,
    scope: $scope,
    iterations: $iterations,
    final_status: $final_status,
    metrics: { start: $metrics_start, end: $metrics_end },
    delta: ($delta | tonumber),
    improvements_made: $improvements
  }')

archive_run "$RUN_ARCHIVE" "$HISTORY_DIR" "$METRICS_FILE"

# ---------------------------------------------------------------------------
# Update state.json
# ---------------------------------------------------------------------------
if [ -f ".forge/state.json" ] && command -v jq >/dev/null 2>&1; then
  TMP_STATE=$(mktemp)
  jq --arg phase "$FINAL_STATUS" '.phase = $phase' ".forge/state.json" > "$TMP_STATE" && mv "$TMP_STATE" ".forge/state.json"
fi

# ---------------------------------------------------------------------------
# Update progress log
# ---------------------------------------------------------------------------
update_progress "$PROGRESS_FILE" \
  "Forge Loop [${FINAL_STATUS}] — ${ITERATION} iteration(s) — Scope: ${SCOPE} — ${SUMMARY}" \
  "$SESSION_ID"

# ---------------------------------------------------------------------------
# Critical notifications
# ---------------------------------------------------------------------------
if [ "$FINAL_STATUS" = "error" ]; then
  notify_critical "Forge Loop ERROR after ${ITERATION} iterations. Scope: ${SCOPE}. Session: ${SESSION_ID}" "HALT"
elif [ "$FINAL_STATUS" = "blocked" ]; then
  notify_critical "Forge Loop BLOCKED — human input required. Scope: ${SCOPE}. Session: ${SESSION_ID}" "HALT"
fi

log_info "Forge Loop ${FINAL_STATUS} | ${ITERATION} iteration(s) | Scope: ${SCOPE}"

# ---------------------------------------------------------------------------
# Exit
# ---------------------------------------------------------------------------
case "$FINAL_STATUS" in
  "complete") exit 0 ;;
  "blocked")  exit 2 ;;
  *)          exit 1 ;;
esac
