#!/usr/bin/env bash
# ~/.claude/loops/build.sh
# CC-Forge: Build loop controller
#
# Runs headless TDD build execution against an approved plan.
# Claude executes one task at a time; this script controls sequencing.
#
# Usage:
#   build.sh <plan-path>                  # run all tasks
#   build.sh plan-auth.md --task T003     # start from a specific task (resume)
#   build.sh plan-auth.md --workspace-toml ~/.claude/forge/workspaces/applications/workspace.toml
#
# Exit codes:
#   0 = all tasks complete and tests passing
#   1 = error or test failure (check progress log for SESSION_ID to resume)
#   2 = blocked (human input required)
#
# Requires: jq, dasel, claude CLI, bash 4.0+ (brew install bash on macOS)

set -euo pipefail

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
PLAN_PATH=""
START_TASK=""
WORKSPACE_TOML=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --task)           START_TASK="$2";      shift 2 ;;
    --workspace-toml) WORKSPACE_TOML="$2";  shift 2 ;;
    -*)
      printf 'Unknown flag: %s\n' "$1" >&2
      printf 'Usage: build.sh <plan-path> [--task T001] [--workspace-toml <path>]\n' >&2
      exit 1
      ;;
    *)
      if [ -z "$PLAN_PATH" ]; then
        PLAN_PATH="$1"
      else
        log_error "Unexpected argument: $1"
        exit 1
      fi
      shift
      ;;
  esac
done

if [ -z "$PLAN_PATH" ]; then
  printf 'Usage: build.sh <plan-path> [--task T001] [--workspace-toml <path>]\n' >&2
  printf 'Example: build.sh plan-auth.md\n' >&2
  exit 1
fi

if [ ! -f "$PLAN_PATH" ]; then
  log_error "Plan file not found: $PLAN_PATH"
  exit 1
fi

export WORKSPACE_TOML

# ---------------------------------------------------------------------------
# Extract task list from plan markdown
# Matches: "### T001: Title" or "### T001 —" patterns
# ---------------------------------------------------------------------------
extract_tasks() {
  local plan_file="$1"
  # Match lines like "### T001:" or "### T001 " (with any separator after the ID)
  grep -oE '(?<=### )(T[0-9]+)(?=:| )' "$plan_file" 2>/dev/null \
    || grep -E '^### T[0-9]+[: ]' "$plan_file" | sed -E 's/^### (T[0-9]+).*/\1/' \
    || true
}

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCHEMA_FILE="${LIB_DIR}/build-signal-schema.json"
LOCKFILE=".forge/build.lock"
HISTORY_DIR=".forge/history"
METRICS_FILE=".forge/metrics/forge-metrics.jsonl"
PROGRESS_FILE="claude-progress.txt"

if [ ! -f "$SCHEMA_FILE" ]; then
  log_error "Schema file not found: $SCHEMA_FILE"
  log_error "Reinstall CC-Forge: ~/.claude/forge/install.sh --global"
  exit 1
fi

TEMP_OUTPUT=$(mktemp /tmp/forge-build-output.XXXXXX.json)

cleanup() {
  rm -f "$TEMP_OUTPUT"
  release_lock "$LOCKFILE" 2>/dev/null || true
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Acquire lock
# ---------------------------------------------------------------------------
acquire_lock "$LOCKFILE" || exit 1

# ---------------------------------------------------------------------------
# Extract and validate task list
# ---------------------------------------------------------------------------
mapfile -t ALL_TASKS < <(extract_tasks "$PLAN_PATH")

if [ ${#ALL_TASKS[@]} -eq 0 ]; then
  log_error "No tasks found in plan: $PLAN_PATH"
  log_error "Expected task headers in format: ### T001: Task Title"
  log_error "Check the plan file format — tasks must use the CC-Forge plan template."
  exit 1
fi

log_info "Found ${#ALL_TASKS[@]} task(s): ${ALL_TASKS[*]}"

# Build the execution list (possibly starting from a specific task)
TASK_LIST=("${ALL_TASKS[@]}")
if [ -n "$START_TASK" ]; then
  START_IDX=-1
  for i in "${!ALL_TASKS[@]}"; do
    if [ "${ALL_TASKS[$i]}" = "$START_TASK" ]; then
      START_IDX="$i"
      break
    fi
  done
  if [ "$START_IDX" -eq -1 ]; then
    log_error "Task '$START_TASK' not found in plan. Available: ${ALL_TASKS[*]}"
    exit 1
  fi
  TASK_LIST=("${ALL_TASKS[@]:$START_IDX}")
  log_info "Resuming from task $START_TASK (skipping ${START_IDX} already-completed task(s))"
fi

# ---------------------------------------------------------------------------
# Run the build loop
# ---------------------------------------------------------------------------
SESSION_ID=""
COMPLETED_TASKS=()
FINAL_STATUS="complete"
LAST_TASK="${ALL_TASKS[-1]}"
RUN_START=$(date '+%Y-%m-%dT%H:%M:%SZ')
TRACE_ID="build-$(date '+%Y%m%d-%H%M%S')"

log_info "Build starting | Plan: ${PLAN_PATH} | Tasks to run: ${#TASK_LIST[@]}"

# Update state.json phase to 'building'
if [ -f ".forge/state.json" ] && command -v jq >/dev/null 2>&1; then
  TMP_STATE=$(mktemp)
  jq '.phase = "building"' ".forge/state.json" > "$TMP_STATE" && mv "$TMP_STATE" ".forge/state.json"
fi

for TASK_ID in "${TASK_LIST[@]}"; do
  log_info "─── Task ${TASK_ID} ────────────────────────────────────"

  # Build the task prompt
  PROMPT=$(cat <<EOF
You are executing BUILD mode for CC-Forge.

Plan file: ${PLAN_PATH}
Current task: ${TASK_ID}
Timestamp: $(date '+%Y-%m-%dT%H:%M:%SZ')

Read the instructions in ~/.claude/commands/forge--build.md.
Execute exactly the task marked as ${TASK_ID} in the plan.

Follow TDD discipline: write failing test → implement minimum code → verify passing → commit.

You MUST output ONLY a valid JSON object. No markdown, no explanation, no other text.
The output must conform to the build-signal-schema.json contract.
EOF
)

  # Build --resume flag
  RESUME_FLAG=()
  if [ -n "$SESSION_ID" ]; then
    RESUME_FLAG=(--resume "$SESSION_ID")
  fi

  # Invoke Claude for this task
  if ! claude \
    -p "$PROMPT" \
    --output-format json \
    --json-schema "$(cat "$SCHEMA_FILE")" \
    --allowedTools "Read,Edit,Bash,Glob,Grep" \
    "${RESUME_FLAG[@]}" \
    > "$TEMP_OUTPUT" 2>/dev/null; then
    log_error "Claude CLI exited non-zero on task ${TASK_ID}"
    FINAL_STATUS="error"
    break
  fi

  # Validate output
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
  TESTS_PASSED=$(parse_field "$TEMP_OUTPUT" '.structured_output.tests_passed' "false")
  SUMMARY=$(parse_field "$TEMP_OUTPUT" '.structured_output.summary' "(no summary)")
  COMMIT_HASH=$(parse_field "$TEMP_OUTPUT" '.structured_output.commit_hash' "")

  log_info "Status: ${STATUS} | Tests: ${TESTS_PASSED} | ${SUMMARY}"
  [ -n "$COMMIT_HASH" ] && log_info "Commit: ${COMMIT_HASH}"

  # Gate: tests must pass before proceeding to the next task
  if [ "$TESTS_PASSED" != "true" ]; then
    log_error "Tests did not pass after task ${TASK_ID} — build halted"
    log_error "Fix the test failures, then resume: build.sh ${PLAN_PATH} --task ${TASK_ID}"
    log_error "Session ID for context: ${SESSION_ID}"
    FINAL_STATUS="failed"
    break
  fi

  COMPLETED_TASKS+=("$TASK_ID")

  # Update progress log after each successful task
  COMMIT_INFO=""
  [ -n "$COMMIT_HASH" ] && COMMIT_INFO=" (${COMMIT_HASH})"
  update_progress "$PROGRESS_FILE" \
    "[${TASK_ID}] ${STATUS} — ${SUMMARY}${COMMIT_INFO}" \
    "$SESSION_ID"

  # Update state.json with progress
  if [ -f ".forge/state.json" ] && command -v jq >/dev/null 2>&1; then
    COMPLETED_JSON=$(printf '%s\n' "${COMPLETED_TASKS[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")
    TMP_STATE=$(mktemp)
    jq --arg task "$TASK_ID" \
       --argjson completed "$COMPLETED_JSON" \
       '.build.current_task = $task | .build.completed_tasks = $completed' \
       ".forge/state.json" > "$TMP_STATE" && mv "$TMP_STATE" ".forge/state.json"
  fi

  # Branch on status
  case "$STATUS" in
    "next")
      log_info "Task ${TASK_ID} complete — proceeding to next task"
      ;;
    "complete")
      log_info "All tasks complete (Claude signaled at ${TASK_ID})"
      FINAL_STATUS="complete"
      break
      ;;
    "blocked")
      BLOCKER_COUNT=$(jq '.structured_output.blockers | length' "$TEMP_OUTPUT" 2>/dev/null || echo "?")
      log_warn "Build blocked at task ${TASK_ID} — ${BLOCKER_COUNT} blocker(s)"
      log_warn "Summary: ${SUMMARY}"
      log_warn "To resume after resolving blockers: build.sh ${PLAN_PATH} --task ${TASK_ID}"
      log_warn "Session ID: ${SESSION_ID}"
      FINAL_STATUS="blocked"
      break
      ;;
    "failed")
      log_error "Build failed at task ${TASK_ID}: ${SUMMARY}"
      log_error "Session ID: ${SESSION_ID}"
      FINAL_STATUS="failed"
      break
      ;;
    *)
      log_error "Unknown status signal: '${STATUS}' at task ${TASK_ID}"
      FINAL_STATUS="error"
      break
      ;;
  esac
done

# If we processed all tasks in our list without an early exit, we're complete
if [ ${#COMPLETED_TASKS[@]} -eq ${#TASK_LIST[@]} ] && [ "$FINAL_STATUS" != "blocked" ] && [ "$FINAL_STATUS" != "failed" ]; then
  FINAL_STATUS="complete"
fi

# ---------------------------------------------------------------------------
# Update state.json on completion
# ---------------------------------------------------------------------------
if [ "$FINAL_STATUS" = "complete" ] && [ -f ".forge/state.json" ] && command -v jq >/dev/null 2>&1; then
  TMP_STATE=$(mktemp)
  jq '.phase = "idle" | .build.completed = true' ".forge/state.json" > "$TMP_STATE" && mv "$TMP_STATE" ".forge/state.json"
fi

# ---------------------------------------------------------------------------
# Archive the run
# ---------------------------------------------------------------------------
COMPLETED_JSON=$(printf '%s\n' "${COMPLETED_TASKS[@]}" | jq -R . | jq -s . 2>/dev/null || echo "[]")

RUN_ARCHIVE=$(jq -n \
  --arg timestamp "$RUN_START" \
  --arg trace_id "$TRACE_ID" \
  --arg span_type "build_run" \
  --arg session_id "$SESSION_ID" \
  --arg plan "$PLAN_PATH" \
  --arg final_status "$FINAL_STATUS" \
  --argjson completed "$COMPLETED_JSON" \
  '{
    timestamp: $timestamp,
    trace_id: $trace_id,
    span_type: $span_type,
    session_id: $session_id,
    plan: $plan,
    final_status: $final_status,
    completed_tasks: $completed
  }')

archive_run "$RUN_ARCHIVE" "$HISTORY_DIR" "$METRICS_FILE"
update_progress "$PROGRESS_FILE" \
  "Build [${FINAL_STATUS}] — ${#COMPLETED_TASKS[@]}/${#TASK_LIST[@]} tasks — Plan: ${PLAN_PATH}" \
  "$SESSION_ID"

# ---------------------------------------------------------------------------
# Critical notifications
# ---------------------------------------------------------------------------
if [ "$FINAL_STATUS" = "failed" ] || [ "$FINAL_STATUS" = "error" ]; then
  LAST_COMPLETED="${COMPLETED_TASKS[-1]:-none}"
  notify_critical "Build ${FINAL_STATUS} at task after ${LAST_COMPLETED}. Plan: ${PLAN_PATH}. Session: ${SESSION_ID}" "HALT"
elif [ "$FINAL_STATUS" = "blocked" ]; then
  notify_critical "Build BLOCKED — human input required. Plan: ${PLAN_PATH}. Session: ${SESSION_ID}" "HALT"
fi

log_info "Build ${FINAL_STATUS} | Completed: ${COMPLETED_TASKS[*]:-none}"

# ---------------------------------------------------------------------------
# Exit
# ---------------------------------------------------------------------------
case "$FINAL_STATUS" in
  "complete") exit 0 ;;
  "blocked")  exit 2 ;;
  *)          exit 1 ;;
esac
