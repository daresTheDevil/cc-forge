#!/usr/bin/env bash
# tests/test-recon-harvest-t008.sh
# TDD test for T008: Add harvest classification logic to /forge--recon command
#
# Acceptance criteria (from plan T008):
#   AC1: commands/recon.md has a Phase 7 "Harvest Pass" section
#   AC2: Phase 7 includes entity classification table with global candidates:
#        database, service (external), pipeline_stage, k8s_resource (cluster-level)
#   AC3: Phase 7 includes project-only classification (api_endpoint, ui_component,
#        service the app itself) with explicit "do NOT harvest" instruction
#   AC4: Phase 7 references conflict detection using bin/harvest-merge.sh
#   AC5: Phase 7 shows a proposed harvest diff to the user before writing
#   AC6: Phase 7 requires user confirmation before writing to global-graph.json
#   AC7: Phase 7 references ~/.claude/forge/registry/global-graph.json as target
#   AC8: Phase 7 includes headless/scripted mode instructions via harvest-merge.sh

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
RECON_CMD="${REPO_DIR}/commands/recon.md"

# ---------------------------------------------------------------------------
# AC1: commands/recon.md has Phase 7 "Harvest Pass" section
# ---------------------------------------------------------------------------
printf '\nAC1: commands/recon.md has Phase 7 Harvest Pass section\n'

if [ ! -f "$RECON_CMD" ]; then
  printf '  FATAL: commands/recon.md not found at %s\n' "$RECON_CMD"
  printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
  exit 1
fi

if grep -q "Phase 7" "$RECON_CMD" && grep -q "[Hh]arvest" "$RECON_CMD"; then
  assert_pass "Phase 7 Harvest Pass section exists in recon.md"
else
  assert_fail "Phase 7 Harvest Pass section exists in recon.md" \
    "missing 'Phase 7' or 'Harvest' in commands/recon.md"
fi

# ---------------------------------------------------------------------------
# AC2: Phase 7 includes global candidate entity kinds
# ---------------------------------------------------------------------------
printf '\nAC2: Phase 7 includes global candidate entity kinds\n'

GLOBAL_KINDS=("database" "pipeline_stage" "k8s_resource" "Global candidate")

for kind in "${GLOBAL_KINDS[@]}"; do
  if grep -q "$kind" "$RECON_CMD"; then
    assert_pass "recon.md references global candidate kind: '$kind'"
  else
    assert_fail "recon.md references global candidate kind: '$kind'" \
      "'$kind' not found in commands/recon.md"
  fi
done

# ---------------------------------------------------------------------------
# AC3: Phase 7 includes project-only classification with "do NOT harvest"
# ---------------------------------------------------------------------------
printf '\nAC3: Phase 7 includes project-only classification (do NOT harvest)\n'

PROJECT_ONLY_KINDS=("api_endpoint" "ui_component")

for kind in "${PROJECT_ONLY_KINDS[@]}"; do
  if grep -q "$kind" "$RECON_CMD"; then
    assert_pass "recon.md references project-only kind: '$kind'"
  else
    assert_fail "recon.md references project-only kind: '$kind'" \
      "'$kind' not found in commands/recon.md"
  fi
done

if grep -qi "do NOT harvest\|do not harvest\|Project-only" "$RECON_CMD"; then
  assert_pass "recon.md contains 'do NOT harvest' or 'Project-only' instruction"
else
  assert_fail "recon.md contains 'do NOT harvest' or 'Project-only' instruction" \
    "no 'do NOT harvest' or 'Project-only' instruction found"
fi

# ---------------------------------------------------------------------------
# AC4: Phase 7 references conflict detection using bin/harvest-merge.sh
# ---------------------------------------------------------------------------
printf '\nAC4: Phase 7 references bin/harvest-merge.sh for conflict detection\n'

if grep -q "harvest-merge.sh" "$RECON_CMD"; then
  assert_pass "recon.md references harvest-merge.sh"
else
  assert_fail "recon.md references harvest-merge.sh" \
    "'harvest-merge.sh' not found in commands/recon.md"
fi

if grep -q "[Cc]onflict" "$RECON_CMD"; then
  assert_pass "recon.md mentions conflict detection"
else
  assert_fail "recon.md mentions conflict detection" \
    "'conflict' not found in commands/recon.md"
fi

# ---------------------------------------------------------------------------
# AC5: Phase 7 shows a proposed harvest diff to the user before writing
# ---------------------------------------------------------------------------
printf '\nAC5: Phase 7 shows proposed harvest diff to user\n'

if grep -qi "proposed\|diff\|harvest diff" "$RECON_CMD"; then
  assert_pass "recon.md mentions proposed diff/review before writing"
else
  assert_fail "recon.md mentions proposed diff/review before writing" \
    "no 'proposed' or 'diff' reference found in commands/recon.md"
fi

# ---------------------------------------------------------------------------
# AC6: Phase 7 requires user confirmation before writing to global-graph.json
# ---------------------------------------------------------------------------
printf '\nAC6: Phase 7 requires user confirmation before writing\n'

if grep -qi "confirm\|confirmation\|ask\|Proceed" "$RECON_CMD"; then
  assert_pass "recon.md requires user confirmation before writing"
else
  assert_fail "recon.md requires user confirmation before writing" \
    "no confirmation/ask/Proceed language found in commands/recon.md"
fi

# ---------------------------------------------------------------------------
# AC7: Phase 7 references the global graph target path
# ---------------------------------------------------------------------------
printf '\nAC7: Phase 7 references ~/.claude/forge/registry/global-graph.json\n'

if grep -q "global-graph.json" "$RECON_CMD"; then
  assert_pass "recon.md references global-graph.json"
else
  assert_fail "recon.md references global-graph.json" \
    "'global-graph.json' not found in commands/recon.md"
fi

# ---------------------------------------------------------------------------
# AC8: Phase 7 includes headless/scripted mode via harvest-merge.sh
# ---------------------------------------------------------------------------
printf '\nAC8: Phase 7 includes headless/scripted mode instructions\n'

if grep -qi "headless\|scripted\|scripting\|non-interactive" "$RECON_CMD"; then
  assert_pass "recon.md mentions headless/scripted mode"
else
  assert_fail "recon.md mentions headless/scripted mode" \
    "no headless/scripted mode reference found in commands/recon.md"
fi

# Exit codes documented for scripted use
if grep -q "exit code\|Exit code" "$RECON_CMD"; then
  assert_pass "recon.md documents exit codes for scripted use"
else
  assert_fail "recon.md documents exit codes for scripted use" \
    "no exit code documentation found in commands/recon.md"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
