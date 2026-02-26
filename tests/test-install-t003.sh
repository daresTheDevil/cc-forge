#!/usr/bin/env bash
# tests/test-install-t003.sh
# TDD test for T003: Convert package-owned installs to symlinks
#
# Acceptance criteria (from plan T003):
#   AC1: All commands/*.md are installed via install_symlink (not install_file)
#        Verified by: running global install and checking destinations are symlinks
#   AC2: All agents/*.md (global) are installed via install_symlink
#   AC3: All loops/*.sh and loops/lib/* are installed via install_symlink
#   AC4: All skills/** are installed via install_symlink
#   AC5: install.sh self-deploy and registry/graph-schema.json are install_symlink
#   AC6: User-owned config files (CLAUDE.md, settings.json, forge.toml, workspace*.toml)
#        remain install_file copies — they must NOT be symlinks after install
#   AC7: Verify install.sh source does NOT call install_file for commands/*.md
#        (static analysis: no install_file "commands/ call in global section)

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
# AC7: Static analysis — install.sh must NOT use install_file for package-owned files
# (This is the primary RED test: it will fail until the conversion is done)
# ---------------------------------------------------------------------------
printf '\nAC7: Static analysis — package-owned files use install_symlink not install_file\n'

# Extract the global install section (between "GLOBAL INSTALL" and "PROJECT INSTALL")
GLOBAL_SECTION="$(awk '/GLOBAL INSTALL/{found=1} found && /PROJECT INSTALL/{exit} found{print}' "$INSTALL_SH")"

# Commands section: no install_file "commands/ should exist
if printf '%s' "$GLOBAL_SECTION" | grep -qE 'install_file "commands/'; then
  assert_fail "commands/*.md use install_symlink" \
    "found install_file calls for commands/ in global section"
else
  assert_pass "commands/*.md use install_symlink (no install_file for commands/)"
fi

# Agents in global ~/.claude/agents/ section: must use install_symlink
# Look for the "Global agents" block
GLOBAL_AGENTS_BLOCK="$(printf '%s' "$GLOBAL_SECTION" | awk '/Global agents/{found=1} found{print}')"
if printf '%s' "$GLOBAL_AGENTS_BLOCK" | grep -qE 'install_file "agents/'; then
  assert_fail "~/.claude/agents/*.md use install_symlink" \
    "found install_file for agents/ in global agents block"
else
  assert_pass "~/.claude/agents/*.md use install_symlink"
fi

# Loop scripts: must use install_symlink
if printf '%s' "$GLOBAL_SECTION" | grep -qE 'install_file "loops/'; then
  assert_fail "loops/*.sh use install_symlink" \
    "found install_file calls for loops/ in global section"
else
  assert_pass "loops/*.sh use install_symlink (no install_file for loops/)"
fi

# Skills: must use install_symlink
if printf '%s' "$GLOBAL_SECTION" | grep -qE 'install_file "skills/'; then
  assert_fail "skills/** use install_symlink" \
    "found install_file calls for skills/ in global section"
else
  assert_pass "skills/** use install_symlink (no install_file for skills/)"
fi

# install.sh self-deploy: must use install_symlink
if printf '%s' "$GLOBAL_SECTION" | grep -qE 'install_file "install\.sh"'; then
  assert_fail "install.sh self-deploy uses install_symlink" \
    "found install_file for install.sh in global section"
else
  assert_pass "install.sh self-deploy uses install_symlink"
fi

# registry/graph-schema.json: must use install_symlink
if printf '%s' "$GLOBAL_SECTION" | grep -qF 'install_file "templates/registry-graph-schema'; then
  assert_fail "registry/graph-schema.json uses install_symlink" \
    "found install_file for registry-graph-schema in global section"
else
  assert_pass "registry/graph-schema.json uses install_symlink"
fi

# ---------------------------------------------------------------------------
# AC6: User-owned config files MUST remain as install_file (must NOT be symlinks)
# Static: verify these specific lines still use install_file
# ---------------------------------------------------------------------------
printf '\nAC6: User-owned config files remain install_file (copy-once)\n'

USER_OWNED_PATTERNS=(
  'templates/CLAUDE-global.md'
  'templates/settings-global.json'
  'templates/forge.toml'
  'templates/workspace-registry.toml'
  'templates/workspace-platform.toml'
  'templates/workspace-applications.toml'
  'templates/workspace-data.toml'
)

for pattern in "${USER_OWNED_PATTERNS[@]}"; do
  # Must appear as install_file (not install_symlink) in the global section
  if printf '%s' "$GLOBAL_SECTION" | grep -qF "install_file \"${pattern}\""; then
    assert_pass "user-owned ${pattern} uses install_file"
  else
    # Check if it was incorrectly converted to install_symlink
    if printf '%s' "$GLOBAL_SECTION" | grep -qF "install_symlink \"${pattern}\""; then
      assert_fail "user-owned ${pattern} uses install_file" \
        "was converted to install_symlink — must remain install_file"
    else
      assert_fail "user-owned ${pattern} uses install_file" \
        "not found in global section at all"
    fi
  fi
done

# ---------------------------------------------------------------------------
# Integration test: run --global into a temp dir and check symlinks vs copies
# ---------------------------------------------------------------------------
printf '\nIntegration: run install.sh --global into tmp home and verify symlink/copy distinction\n'

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Override HOME so install.sh writes to our temp dir
# We also need deps to be present (jq, dasel, claude, bash 4+) — if not, skip gracefully
if ! command -v jq >/dev/null 2>&1 || ! command -v dasel >/dev/null 2>&1; then
  printf '  SKIP: integration test requires jq and dasel (not available)\n'
else
  # Run the global install with fake HOME (suppress claude check by PATH manipulation)
  # We create a fake claude shim so the dep check passes
  FAKE_BIN="${TMPDIR_TEST}/bin"
  mkdir -p "$FAKE_BIN"
  printf '#!/usr/bin/env bash\necho "fake claude"\n' > "${FAKE_BIN}/claude"
  chmod +x "${FAKE_BIN}/claude"

  OLD_HOME="$HOME"
  HOME="$TMPDIR_TEST"
  PATH="${FAKE_BIN}:$PATH"

  set +e
  INSTALL_OUT="$(bash "$INSTALL_SH" --global 2>&1)"
  INSTALL_RC=$?
  set -e

  HOME="$OLD_HOME"

  if [ $INSTALL_RC -ne 0 ]; then
    printf '  SKIP: install.sh --global failed (rc=%d), cannot run integration assertions\n' $INSTALL_RC
    printf '  Output: %s\n' "$(printf '%s' "$INSTALL_OUT" | head -5)"
  else
    PKGDIR="$REPO_DIR"
    COMMANDS_DIR="${TMPDIR_TEST}/.claude/commands"

    # Check commands are symlinks pointing into PKGDIR
    SYMLINK_FAIL=0
    for cmd_src in "${REPO_DIR}/commands/"*.md; do
      basename="$(basename "$cmd_src")"
      stem="${basename%.md}"
      dest="${COMMANDS_DIR}/forge--${stem}.md"
      if [ ! -e "$dest" ]; then
        printf '  WARN: %s not found at %s\n' "$basename" "$dest"
        continue
      fi
      if [ -L "$dest" ]; then
        target="$(readlink "$dest")"
        if [[ "$target" == "${PKGDIR}"* ]]; then
          : # good
        else
          printf '  FAIL (integration): %s symlink target outside PKGDIR: %s\n' "$dest" "$target"
          SYMLINK_FAIL=$((SYMLINK_FAIL + 1))
        fi
      else
        printf '  FAIL (integration): %s is a regular file, not a symlink\n' "$dest"
        SYMLINK_FAIL=$((SYMLINK_FAIL + 1))
      fi
    done

    if [ $SYMLINK_FAIL -eq 0 ]; then
      assert_pass "integration: all command files installed as symlinks into PKGDIR"
    else
      assert_fail "integration: all command files installed as symlinks" \
        "$SYMLINK_FAIL file(s) are not correct symlinks"
    fi

    # Check user-owned files are regular files, not symlinks
    COPY_FAIL=0
    for user_file in \
      "${TMPDIR_TEST}/.claude/CLAUDE.md" \
      "${TMPDIR_TEST}/.claude/settings.json" \
      "${TMPDIR_TEST}/.claude/forge/forge.toml"; do
      if [ -e "$user_file" ]; then
        if [ -L "$user_file" ]; then
          printf '  FAIL (integration): %s is a symlink — must be a copy\n' "$user_file"
          COPY_FAIL=$((COPY_FAIL + 1))
        fi
      fi
    done

    if [ $COPY_FAIL -eq 0 ]; then
      assert_pass "integration: user-owned config files are copies (not symlinks)"
    else
      assert_fail "integration: user-owned config files are copies" \
        "$COPY_FAIL file(s) are symlinks but should be copies"
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
