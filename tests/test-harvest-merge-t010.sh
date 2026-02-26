#!/usr/bin/env bash
# tests/test-harvest-merge-t010.sh
# TDD test for T010: Conflict detection on harvest merge
#
# Acceptance criteria (from plan T010):
#   AC1: Same id, same data → skip (entity count and content unchanged)
#   AC2: Same id, different metadata → exits with code 2 to signal conflict (human review needed)
#   AC3: Same id, existing has constraints → constraints preserved, never dropped on merge
#   AC4: New entity (no conflict) → appended cleanly
#   AC5: Script exists at bin/harvest-merge.sh

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
MERGE_SCRIPT="${REPO_DIR}/bin/harvest-merge.sh"

# ---------------------------------------------------------------------------
# AC5 (static, checked first so failures are obvious): script exists
# ---------------------------------------------------------------------------
printf '\nAC5: Static — harvest-merge.sh exists at bin/harvest-merge.sh\n'

if [ -f "$MERGE_SCRIPT" ]; then
  assert_pass "bin/harvest-merge.sh exists"
else
  assert_fail "bin/harvest-merge.sh exists" "file not found at $MERGE_SCRIPT"
  printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
  exit 1
fi

# Skip integration tests if jq not available
if ! command -v jq >/dev/null 2>&1; then
  printf '  SKIP: integration tests require jq\n'
  printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi

# ---------------------------------------------------------------------------
# Test harness: shared fixtures
# ---------------------------------------------------------------------------
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Base global graph with one existing infra entity (db-oracle-sws with constraint)
BASE_GRAPH='{
  "version": "1.0",
  "last_updated": "2026-02-25T00:00:00Z",
  "entities": [
    {
      "id": "db-oracle-sws",
      "type": "infra",
      "kind": "database",
      "name": "Oracle SWS/Silver",
      "description": "Oracle SWS Silver database.",
      "constraints": [
        {
          "type": "access",
          "value": "READ ONLY — account-level restriction, no write possible at runtime"
        }
      ]
    },
    {
      "type": "forge-project",
      "name": "dashboard",
      "path": "/tmp/dashboard",
      "registered_at": "2026-02-25T00:00:00Z"
    }
  ],
  "relationships": []
}'

# ---------------------------------------------------------------------------
# AC1: Same id, same data → skip (no change to registry)
# ---------------------------------------------------------------------------
printf '\nAC1: Same id, same data → skip (registry unchanged)\n'

REGISTRY_AC1="${TMPDIR_TEST}/global-graph-ac1.json"
printf '%s' "$BASE_GRAPH" > "$REGISTRY_AC1"

# Candidate entity: identical to what is in the graph
CANDIDATE_AC1='{
  "id": "db-oracle-sws",
  "type": "infra",
  "kind": "database",
  "name": "Oracle SWS/Silver",
  "description": "Oracle SWS Silver database.",
  "constraints": [
    {
      "type": "access",
      "value": "READ ONLY — account-level restriction, no write possible at runtime"
    }
  ]
}'

BEFORE_HASH="$(jq -Sc '.' "$REGISTRY_AC1")"
RC=0
bash "$MERGE_SCRIPT" "$REGISTRY_AC1" "$CANDIDATE_AC1" >/dev/null 2>&1 || RC=$?
AFTER_HASH="$(jq -Sc '.' "$REGISTRY_AC1")"

if [ "$BEFORE_HASH" = "$AFTER_HASH" ]; then
  assert_pass "registry content unchanged when entity is identical"
else
  assert_fail "registry content unchanged when entity is identical" \
    "registry was modified unexpectedly"
fi

if [ "$RC" -eq 0 ]; then
  assert_pass "exit code 0 (no conflict) for identical entity"
else
  assert_fail "exit code 0 (no conflict) for identical entity" "got exit code: $RC"
fi

# ---------------------------------------------------------------------------
# AC2: Same id, different metadata → exit code 2 (conflict — human review)
# ---------------------------------------------------------------------------
printf '\nAC2: Same id, different metadata → exit code 2 (conflict signal)\n'

REGISTRY_AC2="${TMPDIR_TEST}/global-graph-ac2.json"
printf '%s' "$BASE_GRAPH" > "$REGISTRY_AC2"

# Candidate entity: same id but different description (a data conflict)
CANDIDATE_AC2='{
  "id": "db-oracle-sws",
  "type": "infra",
  "kind": "database",
  "name": "Oracle SWS/Silver",
  "description": "CHANGED: different description — conflict scenario"
}'

RC2=0
bash "$MERGE_SCRIPT" "$REGISTRY_AC2" "$CANDIDATE_AC2" >/dev/null 2>&1 || RC2=$?

if [ "$RC2" -eq 2 ]; then
  assert_pass "exit code 2 when metadata conflict detected"
else
  assert_fail "exit code 2 when metadata conflict detected" "got exit code: $RC2"
fi

# Verify registry was NOT silently updated on conflict
ORACLE_DESC="$(jq -r '.entities[] | select(.id == "db-oracle-sws") | .description' "$REGISTRY_AC2")"
if [ "$ORACLE_DESC" = "Oracle SWS Silver database." ]; then
  assert_pass "registry not silently modified on conflict"
else
  assert_fail "registry not silently modified on conflict" \
    "description was changed to: $ORACLE_DESC"
fi

# ---------------------------------------------------------------------------
# AC3: Same id, existing has constraints → constraints preserved, never dropped
# ---------------------------------------------------------------------------
printf '\nAC3: Existing constraints preserved on merge (never dropped)\n'

REGISTRY_AC3="${TMPDIR_TEST}/global-graph-ac3.json"
printf '%s' "$BASE_GRAPH" > "$REGISTRY_AC3"

# Candidate entity: same id, same non-constraint metadata, but NO constraints field
# (simulates a project-graph recon that found the db but didn't record the constraint)
CANDIDATE_AC3='{
  "id": "db-oracle-sws",
  "type": "infra",
  "kind": "database",
  "name": "Oracle SWS/Silver",
  "description": "Oracle SWS Silver database."
}'

RC3=0
bash "$MERGE_SCRIPT" "$REGISTRY_AC3" "$CANDIDATE_AC3" >/dev/null 2>&1 || RC3=$?

# Constraints must still be present after the merge attempt
CONSTRAINTS="$(jq '.entities[] | select(.id == "db-oracle-sws") | .constraints' "$REGISTRY_AC3")"
if [ -n "$CONSTRAINTS" ] && [ "$CONSTRAINTS" != "null" ]; then
  assert_pass "constraints array still present after merge"
else
  assert_fail "constraints array still present after merge" \
    "constraints were dropped (got: $CONSTRAINTS)"
fi

ACCESS_VAL="$(jq -r '.entities[] | select(.id == "db-oracle-sws") | .constraints[] | select(.type == "access") | .value' "$REGISTRY_AC3" 2>/dev/null || true)"
if printf '%s' "$ACCESS_VAL" | grep -q "READ ONLY"; then
  assert_pass "READ ONLY access constraint preserved after merge"
else
  assert_fail "READ ONLY access constraint preserved after merge" \
    "constraint value: '$ACCESS_VAL'"
fi

# ---------------------------------------------------------------------------
# AC4: New entity (no existing match) → appended cleanly
# ---------------------------------------------------------------------------
printf '\nAC4: New entity (no id conflict) → appended to registry\n'

REGISTRY_AC4="${TMPDIR_TEST}/global-graph-ac4.json"
printf '%s' "$BASE_GRAPH" > "$REGISTRY_AC4"

CANDIDATE_AC4='{
  "id": "ext-new-service",
  "type": "infra",
  "kind": "service",
  "name": "New External Service",
  "description": "A brand new service not previously in the global graph"
}'

RC4=0
bash "$MERGE_SCRIPT" "$REGISTRY_AC4" "$CANDIDATE_AC4" >/dev/null 2>&1 || RC4=$?

if [ "$RC4" -eq 0 ]; then
  assert_pass "exit code 0 (no conflict) for new entity"
else
  assert_fail "exit code 0 (no conflict) for new entity" "got exit code: $RC4"
fi

NEW_COUNT="$(jq '[.entities[] | select(.id == "ext-new-service")] | length' "$REGISTRY_AC4")"
if [ "$NEW_COUNT" -eq 1 ]; then
  assert_pass "new entity appended to registry"
else
  assert_fail "new entity appended to registry" "found $NEW_COUNT entries"
fi

# Existing entities must not be disturbed
EXISTING_COUNT="$(jq '.entities | length' "$REGISTRY_AC4")"
if [ "$EXISTING_COUNT" -eq 3 ]; then
  assert_pass "entity count is 3 after append (2 existing + 1 new)"
else
  assert_fail "entity count is 3 after append" "got $EXISTING_COUNT"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
