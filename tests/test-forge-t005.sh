#!/usr/bin/env bash
# tests/test-forge-t005.sh
# TDD test for T005: `forge update` iterates registered projects
#
# Acceptance criteria (from plan T005):
#   AC1: bin/forge update) block reads ~/.claude/forge/registry/global-graph.json
#   AC2: bin/forge update) block iterates entities of type "forge-project"
#   AC3: bin/forge update) skips projects whose directories do not exist (with warning)
#   AC4: bin/forge update) runs `forge init --force` in each valid project directory
#   AC5: bin/forge update) prints a success message after completing all projects

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
# AC1: Static — update) block reads global-graph.json
# ---------------------------------------------------------------------------
printf '\nAC1: Static — update) block references global-graph.json\n'

UPDATE_BLOCK="$(awk '/update\)/{found=1} found{print} found && /^\s*;;/{exit}' "$FORGE_BIN")"

if printf '%s' "$UPDATE_BLOCK" | grep -q 'global-graph.json'; then
  assert_pass "update) block references global-graph.json"
else
  assert_fail "update) block references global-graph.json" \
    "no reference to global-graph.json in update) block"
fi

# ---------------------------------------------------------------------------
# AC2: Static — update) block selects forge-project entities
# ---------------------------------------------------------------------------
printf '\nAC2: Static — update) block selects forge-project type entities\n'

if printf '%s' "$UPDATE_BLOCK" | grep -q 'forge-project'; then
  assert_pass "update) block filters by forge-project type"
else
  assert_fail "update) block filters by forge-project type" \
    "no forge-project type filter in update) block"
fi

# ---------------------------------------------------------------------------
# AC3: Static — update) block handles missing directories with a warning
# ---------------------------------------------------------------------------
printf '\nAC3: Static — update) block warns on missing project directories\n'

if printf '%s' "$UPDATE_BLOCK" | grep -qE 'Skipping|not found'; then
  assert_pass "update) block warns on missing project directories"
else
  assert_fail "update) block warns on missing project directories" \
    "no 'Skipping' or 'not found' warning in update) block"
fi

# ---------------------------------------------------------------------------
# AC4: Static — update) block runs forge init --force
# ---------------------------------------------------------------------------
printf '\nAC4: Static — update) block invokes forge init --force\n'

if printf '%s' "$UPDATE_BLOCK" | grep -q -- '--force'; then
  assert_pass "update) block runs forge init --force for each project"
else
  assert_fail "update) block runs forge init --force for each project" \
    "no --force flag in update) block"
fi

# ---------------------------------------------------------------------------
# AC5: Static — update) block prints a completion message
# ---------------------------------------------------------------------------
printf '\nAC5: Static — update) block prints final success/completion message\n'

if printf '%s' "$UPDATE_BLOCK" | grep -qE 'All done|done\.|complete'; then
  assert_pass "update) block prints final completion message"
else
  assert_fail "update) block prints final completion message" \
    "no completion message found in update) block"
fi

# ---------------------------------------------------------------------------
# AC4+AC3: Integration — forge update iterates registry, skips missing dirs
# ---------------------------------------------------------------------------
printf '\nAC4+AC3: Integration — forge update iterates registered projects\n'

if ! command -v jq >/dev/null 2>&1; then
  printf '  SKIP: integration tests require jq\n'
else
  FAKE_HOME="$(mktemp -d)"
  REGISTRY_DIR="${FAKE_HOME}/.claude/forge/registry"
  REGISTRY="${REGISTRY_DIR}/global-graph.json"
  mkdir -p "$REGISTRY_DIR"

  # Create one real project dir and one ghost (missing) dir
  REAL_PROJECT="$(mktemp -d)"
  GHOST_PROJECT="${FAKE_HOME}/ghost-project"  # intentionally does not exist

  REAL_NAME="$(basename "$REAL_PROJECT")"
  GHOST_NAME="$(basename "$GHOST_PROJECT")"
  NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  jq -n \
    --arg rpath "$REAL_PROJECT" --arg rname "$REAL_NAME" \
    --arg gpath "$GHOST_PROJECT" --arg gname "$GHOST_NAME" \
    --arg ts "$NOW" \
    '{
      "version": "1.0",
      "last_updated": $ts,
      "entities": [
        {"type": "forge-project", "name": $rname, "path": $rpath, "registered_at": $ts},
        {"type": "forge-project", "name": $gname, "path": $gpath, "registered_at": $ts}
      ],
      "relationships": []
    }' > "$REGISTRY"

  # Stub forge init to record which directories it was invoked in
  FORGE_CALLS_LOG="${FAKE_HOME}/forge-calls.log"
  FAKE_FORGE="${FAKE_HOME}/bin/forge"
  mkdir -p "${FAKE_HOME}/bin"
  # Also need npm stub
  cat > "$FAKE_FORGE" <<'STUB'
#!/usr/bin/env bash
# Fake forge — records calls and succeeds for "init"
SUBCMD="${1:-}"
if [ "$SUBCMD" = "init" ]; then
  printf '%s\n' "$PWD" >> "${FORGE_CALLS_LOG}"
  exit 0
fi
# For "update" subcmd, delegate to real forge logic test — not needed here
exit 0
STUB
  chmod +x "$FAKE_FORGE"

  # Stub npm to be a no-op
  FAKE_NPM="${FAKE_HOME}/bin/npm"
  printf '#!/usr/bin/env bash\nprintf "[STUB] npm %s\n" "$*"\nexit 0\n' > "$FAKE_NPM"
  chmod +x "$FAKE_NPM"

  # Override HOME and PATH, then invoke the real forge bin in update mode
  FORGE_CALLS_LOG="$FORGE_CALLS_LOG" \
  HOME="$FAKE_HOME" \
  PATH="${FAKE_HOME}/bin:$PATH" \
    bash "$FORGE_BIN" update 2>/dev/null | true
  UPDATE_OUT="$(HOME="$FAKE_HOME" PATH="${FAKE_HOME}/bin:$PATH" FORGE_CALLS_LOG="$FORGE_CALLS_LOG" bash "$FORGE_BIN" update 2>&1 || true)"

  # AC4: real project directory should appear in the calls log
  if [ -f "$FORGE_CALLS_LOG" ] && grep -q "$REAL_PROJECT" "$FORGE_CALLS_LOG"; then
    assert_pass "AC4: integration — forge init ran in the registered real project"
  else
    assert_fail "AC4: integration — forge init ran in the registered real project" \
      "real project path not found in forge-calls.log"
  fi

  # AC3: output should mention the ghost/missing path
  if printf '%s' "$UPDATE_OUT" | grep -q "$GHOST_NAME\|$GHOST_PROJECT\|Skipping\|not found"; then
    assert_pass "AC3: integration — update warns about missing project directory"
  else
    assert_fail "AC3: integration — update warns about missing project directory" \
      "expected warning about missing directory not found in output"
  fi

  rm -rf "$FAKE_HOME" "$REAL_PROJECT"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
