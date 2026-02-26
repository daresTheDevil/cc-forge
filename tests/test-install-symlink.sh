#!/usr/bin/env bash
# tests/test-install-symlink.sh
# TDD test for the install_symlink function in install.sh
#
# Acceptance criteria (from plan T002):
#   AC1: install_symlink creates a symlink from dest -> ARTIFACTS_DIR/src
#   AC2: install_symlink fails (returns 1) when source file does not exist
#   AC3: install_symlink always relinks — replaces stale copies and outdated symlinks
#   AC4: install_symlink creates parent directories as needed
#   AC5: install_symlink prints the correct success/error messages

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

# ---------------------------------------------------------------------------
# Extract install_symlink from install.sh into a testable harness
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Verify the function exists in install.sh before running tests
if ! grep -q "^install_symlink()" "${REPO_DIR}/install.sh"; then
  printf 'RED: install_symlink() not found in install.sh — function not yet implemented\n'
  exit 1
fi

# Source the install_symlink function in isolation.
# We need to define the variables it depends on (ARTIFACTS_DIR, color vars)
# and mock the logger functions.
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Set up a fake ARTIFACTS_DIR with a source file
ARTIFACTS_DIR="${TMPDIR_TEST}/pkg"
mkdir -p "${ARTIFACTS_DIR}/commands"
printf 'fake command content\n' > "${ARTIFACTS_DIR}/commands/recon.md"

# Minimal color and logger mocks
RED="" YELLOW="" GREEN="" CYAN="" BOLD="" RESET=""
info()    { :; }
success() { printf '[CC-Forge] ✅ %s\n' "$*"; }
warn()    { printf '[CC-Forge] ⚠️  %s\n' "$*"; }
error()   { printf '[CC-Forge] ❌ %s\n' "$*" >&2; }

# Source only the install_symlink function from install.sh
# Extract lines between install_symlink() { ... } — stops at the next top-level function
eval "$(awk '/^install_symlink\(\)/{found=1} found{print} found && /^\}$/{exit}' "${REPO_DIR}/install.sh")"

# ---------------------------------------------------------------------------
# AC1: Creates a symlink from dest -> ARTIFACTS_DIR/src
# ---------------------------------------------------------------------------
printf '\nAC1: install_symlink creates a symlink\n'
DEST="${TMPDIR_TEST}/dest/recon.md"
mkdir -p "$(dirname "$DEST")"
install_symlink "commands/recon.md" "$DEST" >/dev/null 2>&1

if [ -L "$DEST" ]; then
  TARGET="$(readlink "$DEST")"
  EXPECTED="${ARTIFACTS_DIR}/commands/recon.md"
  if [ "$TARGET" = "$EXPECTED" ]; then
    assert_pass "symlink target matches ARTIFACTS_DIR/src"
  else
    assert_fail "symlink target matches ARTIFACTS_DIR/src" "got: $TARGET, want: $EXPECTED"
  fi
else
  assert_fail "dest is a symlink (not a regular file)" "dest is not a symlink"
fi

# ---------------------------------------------------------------------------
# AC2: Returns 1 when source file does not exist
# ---------------------------------------------------------------------------
printf '\nAC2: install_symlink returns 1 when source is missing\n'
DEST2="${TMPDIR_TEST}/dest/missing.md"
RC=0
install_symlink "commands/nonexistent.md" "$DEST2" >/dev/null 2>&1 || RC=$?
if [ "$RC" -eq 1 ]; then
  assert_pass "returns exit code 1 when source not found"
else
  assert_fail "returns exit code 1 when source not found" "got exit code: $RC"
fi
if [ ! -e "$DEST2" ]; then
  assert_pass "does not create dest when source is missing"
else
  assert_fail "does not create dest when source is missing" "dest was created unexpectedly"
fi

# ---------------------------------------------------------------------------
# AC3: Always relinks — replaces stale copy and outdated symlinks
# ---------------------------------------------------------------------------
printf '\nAC3: install_symlink always relinks (replaces stale copies and old symlinks)\n'

# 3a: Replace a stale regular file copy at dest
DEST3A="${TMPDIR_TEST}/dest3a/recon.md"
mkdir -p "$(dirname "$DEST3A")"
printf 'stale copy\n' > "$DEST3A"  # plant a regular file
install_symlink "commands/recon.md" "$DEST3A" >/dev/null 2>&1
if [ -L "$DEST3A" ]; then
  assert_pass "replaces stale regular file with symlink"
else
  assert_fail "replaces stale regular file with symlink" "dest is still not a symlink"
fi

# 3b: Replace an outdated symlink pointing to a different target
DEST3B="${TMPDIR_TEST}/dest3b/recon.md"
mkdir -p "$(dirname "$DEST3B")"
ln -sf "/tmp/old-target.md" "$DEST3B"  # outdated symlink
install_symlink "commands/recon.md" "$DEST3B" >/dev/null 2>&1
TARGET3B="$(readlink "$DEST3B")"
EXPECTED="${ARTIFACTS_DIR}/commands/recon.md"
if [ "$TARGET3B" = "$EXPECTED" ]; then
  assert_pass "replaces outdated symlink with updated symlink"
else
  assert_fail "replaces outdated symlink with updated symlink" "got: $TARGET3B"
fi

# ---------------------------------------------------------------------------
# AC4: Creates parent directories as needed
# ---------------------------------------------------------------------------
printf '\nAC4: install_symlink creates parent directories\n'
DEST4="${TMPDIR_TEST}/nested/deep/dir/recon.md"
install_symlink "commands/recon.md" "$DEST4" >/dev/null 2>&1
if [ -L "$DEST4" ]; then
  assert_pass "creates nested parent directories"
else
  assert_fail "creates nested parent directories" "parent dirs not created or dest not symlink"
fi

# ---------------------------------------------------------------------------
# AC5: Prints success message with dest path
# ---------------------------------------------------------------------------
printf '\nAC5: install_symlink prints success message\n'
DEST5="${TMPDIR_TEST}/dest5/recon.md"
OUTPUT="$(install_symlink "commands/recon.md" "$DEST5" 2>&1)"
if printf '%s' "$OUTPUT" | grep -qF "[CC-Forge]"; then
  assert_pass "prints CC-Forge prefixed message"
else
  assert_fail "prints CC-Forge prefixed message" "output was: $OUTPUT"
fi
if printf '%s' "$OUTPUT" | grep -qF "$DEST5"; then
  assert_pass "success message includes dest path"
else
  assert_fail "success message includes dest path" "output was: $OUTPUT"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
