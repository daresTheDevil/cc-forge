#!/usr/bin/env bash
# tests/test-readme-t007.sh
# TDD test for T007: README documents the new one-command update architecture
#
# Acceptance criteria (from plan T007):
#   AC1: README contains an "Installing" section with `npm install -g cc-forge` + `cc-forge`
#   AC2: README contains an "Adding to a project" section with `forge init`
#   AC3: README contains an "Updating everything" section with `forge update`
#   AC4: README describes what `forge update` does (updates globally and re-initializes projects)
#   AC5: README does not reference the old `cc-forge --global` or `cc-forge --project` install syntax as the primary install path

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
README="${REPO_DIR}/README.md"

if [ ! -f "$README" ]; then
  printf 'FATAL: README.md not found at %s\n' "$README"
  exit 1
fi

# ---------------------------------------------------------------------------
# AC1: README contains an "Installing" section with the new two-command flow
# ---------------------------------------------------------------------------
printf '\nAC1: README contains Installing section with npm install + cc-forge flow\n'

if grep -q 'npm install -g cc-forge' "$README"; then
  assert_pass "README contains 'npm install -g cc-forge'"
else
  assert_fail "README contains 'npm install -g cc-forge'" \
    "pattern not found in README.md"
fi

# The new flow uses `cc-forge` (no flags) after npm install
if grep -qE '^cc-forge[[:space:]]*$' "$README" || grep -q '^cc-forge$' "$README"; then
  assert_pass "README contains bare 'cc-forge' as the setup command"
else
  assert_fail "README contains bare 'cc-forge' as the setup command" \
    "no bare 'cc-forge' line found — README may still show old --global flag syntax"
fi

# ---------------------------------------------------------------------------
# AC2: README contains "Adding to a project" section with `forge init`
# ---------------------------------------------------------------------------
printf '\nAC2: README contains "Adding to a project" section\n'

if grep -qi 'adding to a project\|add.*to.*project' "$README"; then
  assert_pass "README contains an 'Adding to a project' heading/section"
else
  assert_fail "README contains an 'Adding to a project' heading/section" \
    "no 'Adding to a project' section found"
fi

if grep -q 'forge init' "$README"; then
  assert_pass "README contains 'forge init' command"
else
  assert_fail "README contains 'forge init' command" \
    "no 'forge init' found in README.md"
fi

# ---------------------------------------------------------------------------
# AC3: README contains "Updating everything" section with `forge update`
# ---------------------------------------------------------------------------
printf '\nAC3: README contains "Updating everything" section with forge update\n'

if grep -qi 'updating everything\|update everything' "$README"; then
  assert_pass "README contains an 'Updating everything' heading/section"
else
  assert_fail "README contains an 'Updating everything' heading/section" \
    "no 'Updating everything' section found"
fi

if grep -q 'forge update' "$README"; then
  assert_pass "README contains 'forge update' command"
else
  assert_fail "README contains 'forge update' command" \
    "no 'forge update' found in README.md"
fi

# ---------------------------------------------------------------------------
# AC4: README describes what forge update does
# ---------------------------------------------------------------------------
printf '\nAC4: README describes what forge update does\n'

# Should mention both global update and registered projects
if grep -qi 'registered project\|all registered\|re-initializ' "$README"; then
  assert_pass "README describes forge update re-initializing registered projects"
else
  assert_fail "README describes forge update re-initializing registered projects" \
    "no mention of registered projects or re-initialization in README"
fi

# ---------------------------------------------------------------------------
# AC5: Old install syntax is not the primary documented path
# ---------------------------------------------------------------------------
printf '\nAC5: Old --global / --project syntax is not the primary install path\n'

# Count how many times --global appears (old syntax) vs the new bare cc-forge
GLOBAL_COUNT="$(grep -c '\-\-global' "$README" || true)"
BARE_CC_FORGE="$(grep -c '^cc-forge$' "$README" || true)"

# If --global appears more than once it is likely still the primary path
if [ "$GLOBAL_COUNT" -le 1 ]; then
  assert_pass "README uses --global sparingly (not the primary install path)"
else
  assert_fail "README uses --global sparingly (not the primary install path)" \
    "--global appears ${GLOBAL_COUNT} times — may still be the primary documented flow"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
