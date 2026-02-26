#!/usr/bin/env bash
# tests/test-blast-t011.sh
# TDD test for T011: Update /forge--blast to read global graph for cross-project blast radius
#
# Acceptance criteria (from plan T011):
#   AC1: commands/blast.md reads the global graph at
#        ~/.claude/forge/registry/global-graph.json
#   AC2: blast.md surfaces cross-project impact — projects from global
#        graph that share the affected entity are identified
#   AC3: blast.md still reads the project-level graph first (backward
#        compatible — existing Step 1 behavior preserved)
#   AC4: blast.md explains what to do when the project-level graph is
#        absent but the global graph has the entity (graceful degradation)
#   AC5: blast.md references forge-project entries in the global graph
#        to enumerate which OTHER registered projects may be affected

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
BLAST_CMD="${REPO_DIR}/commands/blast.md"

# ---------------------------------------------------------------------------
# AC1: commands/blast.md reads the global graph
# ---------------------------------------------------------------------------
printf '\nAC1: commands/blast.md reads ~/.claude/forge/registry/global-graph.json\n'

if [ ! -f "$BLAST_CMD" ]; then
  printf '  FATAL: commands/blast.md not found at %s\n' "$BLAST_CMD"
  printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
  exit 1
fi

if grep -q "global-graph.json" "$BLAST_CMD"; then
  assert_pass "blast.md references global-graph.json"
else
  assert_fail "blast.md references global-graph.json" \
    "'global-graph.json' not found in commands/blast.md"
fi

# ---------------------------------------------------------------------------
# AC2: blast.md surfaces cross-project impact
# ---------------------------------------------------------------------------
printf '\nAC2: blast.md surfaces cross-project impact\n'

if grep -qi "cross-project\|cross project\|other.*project\|registered project" "$BLAST_CMD"; then
  assert_pass "blast.md mentions cross-project impact"
else
  assert_fail "blast.md mentions cross-project impact" \
    "no cross-project impact language found in commands/blast.md"
fi

# ---------------------------------------------------------------------------
# AC3: blast.md still reads project-level graph (backward compatible)
# ---------------------------------------------------------------------------
printf '\nAC3: blast.md still reads project-level graph (backward compatible)\n'

if grep -q "project-graph.json" "$BLAST_CMD"; then
  assert_pass "blast.md still references project-graph.json"
else
  assert_fail "blast.md still references project-graph.json" \
    "'project-graph.json' not found in commands/blast.md"
fi

# ---------------------------------------------------------------------------
# AC4: blast.md handles missing project-level graph gracefully
# ---------------------------------------------------------------------------
printf '\nAC4: blast.md handles missing project-level graph gracefully\n'

if grep -qi "absent\|non-existent\|not found\|missing\|empty\|does not exist\|no.*registry\|registry.*empty" "$BLAST_CMD"; then
  assert_pass "blast.md mentions graceful handling when graph is absent/empty"
else
  assert_fail "blast.md mentions graceful handling when graph is absent/empty" \
    "no empty/absent/missing registry handling found in commands/blast.md"
fi

# ---------------------------------------------------------------------------
# AC5: blast.md references forge-project entries in global graph
#      to find other affected registered projects
# ---------------------------------------------------------------------------
printf '\nAC5: blast.md references forge-project entries to enumerate affected projects\n'

if grep -qi "forge-project\|registered.*project\|project.*registered" "$BLAST_CMD"; then
  assert_pass "blast.md references forge-project or registered projects"
else
  assert_fail "blast.md references forge-project or registered projects" \
    "no 'forge-project' or 'registered project' reference in commands/blast.md"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
