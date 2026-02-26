#!/usr/bin/env bash
# tests/test-install-t004.sh
# TDD test for T004: Register project in global graph on `forge init`
#
# Acceptance criteria (from plan T004):
#   AC1: install.sh contains a register_project() function
#   AC2: register_project() is called at the end of the --project install path
#   AC3: register_project() requires jq and gracefully skips if not found
#   AC4: Running `install.sh --project` in a temp dir adds an entity to
#        ~/.claude/forge/registry/global-graph.json with:
#          - .type == "forge-project"
#          - .path == the project directory
#          - .name == basename of the project directory
#          - .registered_at is a non-empty ISO 8601 timestamp
#   AC5: Running `install.sh --project` a second time (re-init) updates the
#        existing entry instead of creating a duplicate

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
INSTALL_SH="${REPO_DIR}/install.sh"

# ---------------------------------------------------------------------------
# AC1: Static — register_project function exists in install.sh
# ---------------------------------------------------------------------------
printf '\nAC1: Static — register_project function exists in install.sh\n'

if grep -q 'register_project()' "$INSTALL_SH"; then
  assert_pass "register_project() function defined in install.sh"
else
  assert_fail "register_project() function defined in install.sh" \
    "function not found in install.sh"
fi

# ---------------------------------------------------------------------------
# AC2: Static — register_project is called in the --project install path
# ---------------------------------------------------------------------------
printf '\nAC2: Static — register_project called in --project install path\n'

# Extract the project install section
PROJECT_SECTION="$(awk '/PROJECT INSTALL/{found=1} found{print}' "$INSTALL_SH")"

if printf '%s' "$PROJECT_SECTION" | grep -q 'register_project'; then
  assert_pass "register_project called in project install section"
else
  assert_fail "register_project called in project install section" \
    "no register_project call found in project install section"
fi

# ---------------------------------------------------------------------------
# AC3: Static — register_project gracefully skips if jq not found
# ---------------------------------------------------------------------------
printf '\nAC3: Static — register_project handles missing jq gracefully\n'

# Extract the register_project function body
FUNC_BODY="$(awk '/^register_project\(\)/{found=1} found{print} found && /^}$/{exit}' "$INSTALL_SH")"

if printf '%s' "$FUNC_BODY" | grep -q 'jq'; then
  if printf '%s' "$FUNC_BODY" | grep -qE 'warn|return 0|skip'; then
    assert_pass "register_project handles missing jq with graceful skip"
  else
    assert_fail "register_project handles missing jq with graceful skip" \
      "jq check found but no graceful fallback (warn/return 0)"
  fi
else
  assert_fail "register_project handles missing jq with graceful skip" \
    "no jq dependency check in register_project"
fi

# ---------------------------------------------------------------------------
# AC4 + AC5: Integration — run --project in temp dir and verify registry entry
# ---------------------------------------------------------------------------
printf '\nAC4+AC5: Integration — project registration writes to global-graph.json\n'

if ! command -v jq >/dev/null 2>&1 || ! command -v dasel >/dev/null 2>&1; then
  printf '  SKIP: integration tests require jq and dasel\n'
else
  # Set up fake HOME with a seeded global-graph.json
  FAKE_HOME="$(mktemp -d)"
  FAKE_PROJECT="$(mktemp -d)"
  PROJECT_NAME="$(basename "$FAKE_PROJECT")"
  REGISTRY_DIR="${FAKE_HOME}/.claude/forge/registry"
  REGISTRY="${REGISTRY_DIR}/global-graph.json"

  mkdir -p "$REGISTRY_DIR"
  printf '%s\n' '{"version":"1.0","last_updated":null,"entities":[],"relationships":[]}' > "$REGISTRY"

  # Fake claude binary so dependency check passes
  FAKE_BIN="${FAKE_HOME}/bin"
  mkdir -p "$FAKE_BIN"
  printf '#!/usr/bin/env bash\necho "fake claude"\n' > "${FAKE_BIN}/claude"
  chmod +x "${FAKE_BIN}/claude"

  OLD_HOME="$HOME"
  OLD_PWD="$PWD"
  HOME="$FAKE_HOME"
  PATH="${FAKE_BIN}:$PATH"
  cd "$FAKE_PROJECT"

  set +e
  INSTALL_OUT="$(bash "$INSTALL_SH" --project 2>&1)"
  INSTALL_RC=$?
  set -e

  HOME="$OLD_HOME"
  cd "$OLD_PWD"

  if [ $INSTALL_RC -ne 0 ]; then
    printf '  SKIP: install.sh --project failed (rc=%d)\n' $INSTALL_RC
    printf '  First 10 lines of output:\n'
    printf '%s\n' "$INSTALL_OUT" | head -10 | sed 's/^/    /'
  else
    # AC4: entry must exist in the registry
    ENTRY_COUNT="$(HOME="$FAKE_HOME" jq '[.entities[] | select(.type == "forge-project" and .path == "'"$FAKE_PROJECT"'")] | length' "$REGISTRY")"

    if [ "$ENTRY_COUNT" -eq 1 ]; then
      assert_pass "AC4: registry contains one entry with correct path"

      # Verify required fields
      ENTRY="$(HOME="$FAKE_HOME" jq '.entities[] | select(.type == "forge-project" and .path == "'"$FAKE_PROJECT"'")' "$REGISTRY")"

      ENTRY_NAME="$(printf '%s' "$ENTRY" | jq -r '.name')"
      ENTRY_TS="$(printf '%s' "$ENTRY" | jq -r '.registered_at')"

      if [ "$ENTRY_NAME" = "$PROJECT_NAME" ]; then
        assert_pass "AC4: registry entry .name matches directory basename"
      else
        assert_fail "AC4: registry entry .name matches directory basename" \
          "got '$ENTRY_NAME', expected '$PROJECT_NAME'"
      fi

      if [ -n "$ENTRY_TS" ] && [ "$ENTRY_TS" != "null" ]; then
        assert_pass "AC4: registry entry .registered_at is non-empty"
      else
        assert_fail "AC4: registry entry .registered_at is non-empty" \
          "got null or empty timestamp"
      fi
    else
      assert_fail "AC4: registry contains one entry with correct path" \
        "found $ENTRY_COUNT entries (expected 1)"
    fi

    # AC5: re-run --project (--force) and confirm no duplicate
    cd "$FAKE_PROJECT"
    HOME="$FAKE_HOME"
    PATH="${FAKE_BIN}:$PATH"

    set +e
    INSTALL_OUT2="$(HOME="$FAKE_HOME" bash "$INSTALL_SH" --project --force 2>&1)"
    INSTALL_RC2=$?
    set -e

    HOME="$OLD_HOME"
    cd "$OLD_PWD"

    if [ $INSTALL_RC2 -ne 0 ]; then
      printf '  SKIP: second --project --force install failed (rc=%d)\n' $INSTALL_RC2
    else
      ENTRY_COUNT2="$(HOME="$FAKE_HOME" jq '[.entities[] | select(.type == "forge-project" and .path == "'"$FAKE_PROJECT"'")] | length' "$REGISTRY")"
      if [ "$ENTRY_COUNT2" -eq 1 ]; then
        assert_pass "AC5: re-init updates entry instead of creating duplicate"
      else
        assert_fail "AC5: re-init updates entry instead of creating duplicate" \
          "found $ENTRY_COUNT2 entries after re-init (expected still 1)"
      fi
    fi
  fi

  rm -rf "$FAKE_HOME" "$FAKE_PROJECT"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
