#!/usr/bin/env bash
# tests/test-context-handoff-t011.sh
# TDD test for plan-token-discipline.md T011: Create context-handoff.sh and wire into global install
#
# Acceptance criteria:
#   AC1: hooks/context-handoff.sh exists and is executable
#   AC2: Running the script in a git dir creates .forge/handoffs/handoff-*.md
#        and writes ~/.claude/pending-resume
#   AC3: Script produces zero stdout/stderr output
#   AC4: Script exits 0 when .forge/ does not exist (creates it)
#   AC5: install.sh --global path includes a step to copy/symlink context-handoff.sh
#        to ~/.claude/forge/context-handoff.sh
#   AC6: grep "context-handoff" install.sh returns a match

set -euo pipefail

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
HOOK_FILE="${REPO_DIR}/hooks/context-handoff.sh"
INSTALL_FILE="${REPO_DIR}/install.sh"

# ---------------------------------------------------------------------------
# AC1: hooks/context-handoff.sh exists and is executable
# ---------------------------------------------------------------------------
printf '\nAC1: hooks/context-handoff.sh exists and is executable\n'

if [ -f "$HOOK_FILE" ]; then
  assert_pass "hooks/context-handoff.sh exists"
else
  assert_fail "hooks/context-handoff.sh exists" "file not found at $HOOK_FILE"
fi

if [ -x "$HOOK_FILE" ]; then
  assert_pass "hooks/context-handoff.sh is executable"
else
  assert_fail "hooks/context-handoff.sh is executable" "file is not executable (chmod +x required)"
fi

# ---------------------------------------------------------------------------
# AC2: Running script in a git dir creates handoff file and writes pending-resume
# ---------------------------------------------------------------------------
printf '\nAC2: Script creates .forge/handoffs/handoff-*.md and writes ~/.claude/pending-resume\n'

TMPDIR_TEST=$(mktemp -d)
# Make it a git directory
git init --quiet "$TMPDIR_TEST" 2>/dev/null
ORIG_PENDING_RESUME="${HOME}/.claude/pending-resume"
PENDING_RESUME_BACKUP="${HOME}/.claude/pending-resume.bak.$$"

# Backup pending-resume if it exists
if [ -f "$ORIG_PENDING_RESUME" ]; then
  cp "$ORIG_PENDING_RESUME" "$PENDING_RESUME_BACKUP"
fi

(
  cd "$TMPDIR_TEST"
  bash "$HOOK_FILE" < /dev/null 2>/dev/null
)

HANDOFF_COUNT=$(find "$TMPDIR_TEST/.forge/handoffs" -name "handoff-*.md" 2>/dev/null | wc -l | tr -d ' ')
if [ "$HANDOFF_COUNT" -ge 1 ]; then
  assert_pass "handoff-*.md file created in .forge/handoffs/"
else
  assert_fail "handoff-*.md file created in .forge/handoffs/" \
    "no handoff-*.md found in $TMPDIR_TEST/.forge/handoffs/"
fi

if [ -f "${HOME}/.claude/pending-resume" ]; then
  PR_CONTENT=$(cat "${HOME}/.claude/pending-resume")
  if echo "$PR_CONTENT" | grep -q "handoff-"; then
    assert_pass "~/.claude/pending-resume written with handoff path"
  else
    assert_fail "~/.claude/pending-resume written with handoff path" \
      "pending-resume content does not contain 'handoff-': $PR_CONTENT"
  fi
else
  assert_fail "~/.claude/pending-resume written" "file not found after script run"
fi

# Restore pending-resume
if [ -f "$PENDING_RESUME_BACKUP" ]; then
  mv "$PENDING_RESUME_BACKUP" "$ORIG_PENDING_RESUME"
else
  rm -f "$ORIG_PENDING_RESUME"
fi

rm -rf "$TMPDIR_TEST"

# ---------------------------------------------------------------------------
# AC3: Script produces zero stdout/stderr output
# ---------------------------------------------------------------------------
printf '\nAC3: Script produces zero stdout/stderr output\n'

TMPDIR_SILENT=$(mktemp -d)
git init --quiet "$TMPDIR_SILENT" 2>/dev/null
PENDING_RESUME_BACKUP2="${HOME}/.claude/pending-resume.bak2.$$"

if [ -f "$ORIG_PENDING_RESUME" ]; then
  cp "$ORIG_PENDING_RESUME" "$PENDING_RESUME_BACKUP2"
fi

OUTPUT=$(cd "$TMPDIR_SILENT" && bash "$HOOK_FILE" < /dev/null 2>&1)

if [ -z "$OUTPUT" ]; then
  assert_pass "Script produces no stdout/stderr output"
else
  assert_fail "Script produces no stdout/stderr output" \
    "Unexpected output: $OUTPUT"
fi

if [ -f "$PENDING_RESUME_BACKUP2" ]; then
  mv "$PENDING_RESUME_BACKUP2" "$ORIG_PENDING_RESUME"
else
  rm -f "$ORIG_PENDING_RESUME"
fi

rm -rf "$TMPDIR_SILENT"

# ---------------------------------------------------------------------------
# AC4: Script exits 0 when .forge/ does not exist (creates it)
# ---------------------------------------------------------------------------
printf '\nAC4: Script exits 0 when .forge/ does not exist\n'

TMPDIR_NFORGE=$(mktemp -d)
git init --quiet "$TMPDIR_NFORGE" 2>/dev/null
PENDING_RESUME_BACKUP3="${HOME}/.claude/pending-resume.bak3.$$"

if [ -f "$ORIG_PENDING_RESUME" ]; then
  cp "$ORIG_PENDING_RESUME" "$PENDING_RESUME_BACKUP3"
fi

set +e
(
  cd "$TMPDIR_NFORGE"
  bash "$HOOK_FILE" < /dev/null 2>/dev/null
)
EXIT_CODE=$?
set -e

if [ "$EXIT_CODE" -eq 0 ]; then
  assert_pass "Script exits 0 when .forge/ does not exist"
else
  assert_fail "Script exits 0 when .forge/ does not exist" \
    "Script exited with code $EXIT_CODE"
fi

if [ -f "$PENDING_RESUME_BACKUP3" ]; then
  mv "$PENDING_RESUME_BACKUP3" "$ORIG_PENDING_RESUME"
else
  rm -f "$ORIG_PENDING_RESUME"
fi

rm -rf "$TMPDIR_NFORGE"

# ---------------------------------------------------------------------------
# AC5 + AC6: install.sh references context-handoff.sh in the global section
# ---------------------------------------------------------------------------
printf '\nAC5: install.sh --global section copies/symlinks context-handoff.sh to ~/.claude/forge/\n'

if grep -q "context-handoff" "$INSTALL_FILE"; then
  assert_pass "install.sh references context-handoff"
else
  assert_fail "install.sh references context-handoff" \
    "no 'context-handoff' found in $INSTALL_FILE"
fi

if grep -q "context-handoff.sh" "$INSTALL_FILE"; then
  assert_pass "install.sh references context-handoff.sh (full filename)"
else
  assert_fail "install.sh references context-handoff.sh (full filename)" \
    "no 'context-handoff.sh' found in $INSTALL_FILE"
fi

# Verify the install step is in the global section (before project section)
# Count line numbers
GLOBAL_SECTION_END=$(grep -n '"project"' "$INSTALL_FILE" | head -1 | cut -d: -f1 || echo "9999")
HANDOFF_LINE=$(grep -n "context-handoff.sh" "$INSTALL_FILE" | head -1 | cut -d: -f1 || echo "0")

if [ "$HANDOFF_LINE" -gt 0 ] && [ "$HANDOFF_LINE" -lt "$GLOBAL_SECTION_END" ]; then
  assert_pass "context-handoff.sh install step is in the global section"
else
  assert_fail "context-handoff.sh install step is in the global section" \
    "handoff line=$HANDOFF_LINE, global section ends around=$GLOBAL_SECTION_END"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
