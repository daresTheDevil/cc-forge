#!/usr/bin/env bash
# tests/test-hooks-session-end-t004.sh
# TDD test for T004: Rewrite hooks/session-end.sh
#
# Acceptance criteria (from plan T004):
#   AC1.1 — session-end writes machine-readable JSON state to .forge/logs/last-session.json
#   AC1.2 — session-end warns on dirty tree (stdout message with change count)
#   AC1.6 — hook degrades gracefully without jq (exits 0, no crash)
#   AC4.3 — session-end writes .forge/logs/learn-pending flag file
#
# Verification: execute the script in a temp git directory, assert file creation and exit code

set -uo pipefail

PASS=0
FAIL=0

assert_pass() {
  local label="$1"
  PASS=$((PASS + 1))
  printf '  PASS: %s\n' "$label"
}

assert_fail() {
  local label="$1"
  local reason="${2:-}"
  FAIL=$((FAIL + 1))
  printf '  FAIL: %s%s\n' "$label" "${reason:+ — $reason}"
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
HOOK_SCRIPT="${REPO_DIR}/hooks/session-end.sh"

# ---------------------------------------------------------------------------
# Setup: create a temp git directory for test execution
# ---------------------------------------------------------------------------
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Initialize a bare git repo in the temp dir
git -C "$TMPDIR_TEST" init -q
git -C "$TMPDIR_TEST" config user.email "test@test.com"
git -C "$TMPDIR_TEST" config user.name "Test"

# ---------------------------------------------------------------------------
# AC1.1 + AC4.3: Clean tree — last-session.json and learn-pending are written
# ---------------------------------------------------------------------------
printf '\nAC1.1 + AC4.3: last-session.json and learn-pending written on clean tree\n'

(cd "$TMPDIR_TEST" && bash "$HOOK_SCRIPT" < /dev/null)
EXIT_CODE=$?

if [ "$EXIT_CODE" -eq 0 ]; then
  assert_pass "AC exit 0 on clean tree"
else
  assert_fail "AC exit 0 on clean tree" "exit code was $EXIT_CODE"
fi

if [ -f "${TMPDIR_TEST}/.forge/logs/last-session.json" ]; then
  assert_pass "AC1.1 — .forge/logs/last-session.json exists"
else
  assert_fail "AC1.1 — .forge/logs/last-session.json exists" "file not found"
fi

if [ -f "${TMPDIR_TEST}/.forge/logs/learn-pending" ]; then
  assert_pass "AC4.3 — .forge/logs/learn-pending flag file exists"
else
  assert_fail "AC4.3 — .forge/logs/learn-pending flag file exists" "file not found"
fi

# ---------------------------------------------------------------------------
# AC1.1: Validate JSON structure — all five required fields present
# ---------------------------------------------------------------------------
printf '\nAC1.1: Validate last-session.json contains all five required fields\n'

if command -v jq >/dev/null 2>&1; then
  JSON_FILE="${TMPDIR_TEST}/.forge/logs/last-session.json"

  # Validate it is parseable JSON
  if jq . "$JSON_FILE" >/dev/null 2>&1; then
    assert_pass "AC1.1 — last-session.json is valid JSON"
  else
    assert_fail "AC1.1 — last-session.json is valid JSON" "jq parse failed"
  fi

  # Check each required field is present (not null)
  for field in ended_at branch uncommitted_changes forge_phase forge_task; do
    val=$(jq -r --arg f "$field" '.[$f]' "$JSON_FILE" 2>/dev/null)
    if [ -n "$val" ] && [ "$val" != "null" ]; then
      assert_pass "AC1.1 — field '$field' present and non-null"
    else
      assert_fail "AC1.1 — field '$field' present and non-null" "got: '$val'"
    fi
  done

  # Check uncommitted_changes is an integer (0 for a clean new repo)
  uncommitted=$(jq -r '.uncommitted_changes' "$JSON_FILE" 2>/dev/null)
  if [[ "$uncommitted" =~ ^[0-9]+$ ]]; then
    assert_pass "AC1.1 — uncommitted_changes is an integer"
  else
    assert_fail "AC1.1 — uncommitted_changes is an integer" "got: '$uncommitted'"
  fi
else
  printf '  SKIP: jq not available — skipping JSON field validation\n'
fi

# ---------------------------------------------------------------------------
# AC1.2: Dirty tree — stdout warning contains change count
# ---------------------------------------------------------------------------
printf '\nAC1.2: Dirty tree warning printed to stdout\n'

# Create an untracked file to make the tree dirty
TMPDIR_DIRTY="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_DIRTY"' EXIT
git -C "$TMPDIR_DIRTY" init -q
git -C "$TMPDIR_DIRTY" config user.email "test@test.com"
git -C "$TMPDIR_DIRTY" config user.name "Test"
printf 'dirty\n' > "${TMPDIR_DIRTY}/dirty-file.txt"  # untracked file

DIRTY_OUTPUT="$(cd "$TMPDIR_DIRTY" && bash "$HOOK_SCRIPT" < /dev/null 2>/dev/null)"
DIRTY_EXIT=$?

if [ "$DIRTY_EXIT" -eq 0 ]; then
  assert_pass "AC1.2 — exits 0 on dirty tree"
else
  assert_fail "AC1.2 — exits 0 on dirty tree" "exit code was $DIRTY_EXIT"
fi

# The warning should mention a number > 0
if printf '%s' "$DIRTY_OUTPUT" | grep -qE '[0-9]+'; then
  assert_pass "AC1.2 — stdout warning contains a numeric change count"
else
  assert_fail "AC1.2 — stdout warning contains a numeric change count" \
    "no numeric count found in output: '$DIRTY_OUTPUT'"
fi

# ---------------------------------------------------------------------------
# AC1.6: Graceful degradation without jq
# ---------------------------------------------------------------------------
printf '\nAC1.6: Graceful degradation without jq\n'

TMPDIR_NOJQ="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_NOJQ"' EXIT
git -C "$TMPDIR_NOJQ" init -q
git -C "$TMPDIR_NOJQ" config user.email "test@test.com"
git -C "$TMPDIR_NOJQ" config user.name "Test"

# Run with empty PATH (no jq, no git — should not crash)
# Use full path to bash since PATH="" means bash cannot be found by name
BASH_BIN="$(command -v bash)"
NOJQ_EXIT=$(cd "$TMPDIR_NOJQ" && PATH="" "$BASH_BIN" "$HOOK_SCRIPT" < /dev/null > /dev/null 2>&1; echo $?)

if [ "$NOJQ_EXIT" -eq 0 ]; then
  assert_pass "AC1.6 — exits 0 without jq in PATH"
else
  assert_fail "AC1.6 — exits 0 without jq in PATH" "exit code was $NOJQ_EXIT"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
