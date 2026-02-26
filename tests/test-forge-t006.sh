#!/usr/bin/env bash
# tests/test-forge-t006.sh
# TDD test for T006: forge deinit deregisters project; forge update warns on stale entries
#
# Acceptance criteria (from plan T006):
#   AC1: bin/forge contains a deinit) case in its routing switch
#   AC2: deinit) block removes the current project path from global-graph.json
#   AC3: deinit) block prints a confirmation message on success
#   AC4: deinit) block is a no-op (no error) when registry does not exist
#   AC5: forge update already warns on missing project directories (inherited from T005 AC3)

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
FORGE_BIN="${REPO_DIR}/bin/forge"

# ---------------------------------------------------------------------------
# AC1: Static — bin/forge contains a deinit) case
# ---------------------------------------------------------------------------
printf '\nAC1: Static — bin/forge contains a deinit) routing case\n'

if grep -q 'deinit)' "$FORGE_BIN"; then
  assert_pass "deinit) case present in bin/forge"
else
  assert_fail "deinit) case present in bin/forge" \
    "no 'deinit)' case found in bin/forge"
fi

# ---------------------------------------------------------------------------
# AC2: Static — deinit) block removes path from global-graph.json via jq
# ---------------------------------------------------------------------------
printf '\nAC2: Static — deinit) block removes project path from registry\n'

DEINIT_BLOCK="$(awk '/deinit\)/{found=1} found{print} found && /^\s*;;/{exit}' "$FORGE_BIN")"

if printf '%s' "$DEINIT_BLOCK" | grep -q 'global-graph.json'; then
  assert_pass "deinit) block references global-graph.json"
else
  assert_fail "deinit) block references global-graph.json" \
    "no reference to global-graph.json in deinit) block"
fi

if printf '%s' "$DEINIT_BLOCK" | grep -q 'select\|path\|entities'; then
  assert_pass "deinit) block filters entities by path"
else
  assert_fail "deinit) block filters entities by path" \
    "no jq filter expression (select/path/entities) in deinit) block"
fi

# ---------------------------------------------------------------------------
# AC3: Static — deinit) block prints a confirmation message
# ---------------------------------------------------------------------------
printf '\nAC3: Static — deinit) block prints a confirmation message\n'

if printf '%s' "$DEINIT_BLOCK" | grep -qiE 'removed|deregistered|success|done'; then
  assert_pass "deinit) block prints a confirmation/success message"
else
  assert_fail "deinit) block prints a confirmation/success message" \
    "no confirmation message found in deinit) block"
fi

# ---------------------------------------------------------------------------
# AC4: Integration — forge deinit removes current project from registry
# ---------------------------------------------------------------------------
printf '\nAC4: Integration — forge deinit removes project entry from global-graph.json\n'

if ! command -v jq >/dev/null 2>&1; then
  printf '  SKIP: integration tests require jq\n'
else
  FAKE_HOME="$(mktemp -d)"
  REGISTRY_DIR="${FAKE_HOME}/.claude/forge/registry"
  REGISTRY="${REGISTRY_DIR}/global-graph.json"
  mkdir -p "$REGISTRY_DIR"

  # Create a fake project directory to deinit from
  FAKE_PROJECT="$(mktemp -d)"
  KEEP_PROJECT="$(mktemp -d)"
  FAKE_NAME="$(basename "$FAKE_PROJECT")"
  KEEP_NAME="$(basename "$KEEP_PROJECT")"
  NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  # Seed registry with two projects
  jq -n \
    --arg fpath "$FAKE_PROJECT" --arg fname "$FAKE_NAME" \
    --arg kpath "$KEEP_PROJECT" --arg kname "$KEEP_NAME" \
    --arg ts "$NOW" \
    '{
      "version": "1.0",
      "last_updated": $ts,
      "entities": [
        {"type": "forge-project", "name": $fname, "path": $fpath, "registered_at": $ts},
        {"type": "forge-project", "name": $kname, "path": $kpath, "registered_at": $ts}
      ],
      "relationships": []
    }' > "$REGISTRY"

  # Run forge deinit from the fake project directory (overriding HOME)
  HOME="$FAKE_HOME" bash "$FORGE_BIN" deinit 2>&1 || true

  # The entry for FAKE_PROJECT (which is $PWD when running from default dir) is
  # not necessarily the one we care about — we need to run from FAKE_PROJECT.
  # Reset and run from FAKE_PROJECT directory.
  jq -n \
    --arg fpath "$FAKE_PROJECT" --arg fname "$FAKE_NAME" \
    --arg kpath "$KEEP_PROJECT" --arg kname "$KEEP_NAME" \
    --arg ts "$NOW" \
    '{
      "version": "1.0",
      "last_updated": $ts,
      "entities": [
        {"type": "forge-project", "name": $fname, "path": $fpath, "registered_at": $ts},
        {"type": "forge-project", "name": $kname, "path": $kpath, "registered_at": $ts}
      ],
      "relationships": []
    }' > "$REGISTRY"

  # Run deinit from FAKE_PROJECT so that $PWD matches its path in the registry
  (cd "$FAKE_PROJECT" && HOME="$FAKE_HOME" bash "$FORGE_BIN" deinit 2>&1) || true

  # FAKE_PROJECT should no longer appear in the registry
  REMAINING="$(jq -r '.entities[].path' "$REGISTRY" 2>/dev/null || echo "")"

  if printf '%s' "$REMAINING" | grep -q "$FAKE_PROJECT"; then
    assert_fail "AC4: integration — deinit removes project from registry" \
      "project path still present after deinit: $FAKE_PROJECT"
  else
    assert_pass "AC4: integration — deinit removed project from registry"
  fi

  # KEEP_PROJECT should still be present
  if printf '%s' "$REMAINING" | grep -q "$KEEP_PROJECT"; then
    assert_pass "AC4: integration — deinit preserves other project entries"
  else
    assert_fail "AC4: integration — deinit preserves other project entries" \
      "keep-project path missing after deinit: $KEEP_PROJECT"
  fi

  rm -rf "$FAKE_HOME" "$FAKE_PROJECT" "$KEEP_PROJECT"
fi

# ---------------------------------------------------------------------------
# AC5: Integration — forge deinit is a no-op when registry does not exist
# ---------------------------------------------------------------------------
printf '\nAC5: Integration — forge deinit is a no-op when registry is absent\n'

if ! command -v jq >/dev/null 2>&1; then
  printf '  SKIP: integration tests require jq\n'
else
  FAKE_HOME2="$(mktemp -d)"
  # No registry created — HOME has no global-graph.json

  EXIT_CODE=0
  HOME="$FAKE_HOME2" bash "$FORGE_BIN" deinit 2>&1 || EXIT_CODE=$?

  if [ "$EXIT_CODE" -eq 0 ]; then
    assert_pass "AC5: deinit exits 0 when registry does not exist"
  else
    assert_fail "AC5: deinit exits 0 when registry does not exist" \
      "non-zero exit code $EXIT_CODE when registry absent"
  fi

  rm -rf "$FAKE_HOME2"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
