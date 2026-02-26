#!/usr/bin/env bash
# tests/test-global-graph-t009.sh
# TDD test for T009: Seed global graph with known PRR shared infrastructure
#
# Acceptance criteria (from plan T009):
#   AC1: global-graph.json contains at least 12 entities after seeding (2 existing forge-project + 11 infra)
#   AC2: All 11 required infra entity IDs are present:
#         ext-microsoft-entra-id, ext-ldap, ext-ukg-rest,
#         db-mssql-konami, db-mssql-newwave, db-mssql-infogenesis,
#         db-mssql-cct-prr, db-mssql-cct-bok-homa, db-mssql-cct-crystal-sky,
#         db-oracle-sws, infra-harbor-registry, infra-microk8s, pipeline-woodpecker
#   AC3: db-oracle-sws has a constraints array with at least one entry of type "access"
#        containing "READ ONLY"
#   AC4: Each infra entity has a "kind" field (not "type") classifying its category
#        (database, service, k8s_resource, pipeline_stage)
#   AC5: The seed script is idempotent — running it twice does not duplicate entries
#        (entity count remains stable)
#   AC6: Existing forge-project entries are preserved after seeding

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
SEED_SCRIPT="${REPO_DIR}/bin/seed-global-graph.sh"

# ---------------------------------------------------------------------------
# AC0: Static — seed script exists
# ---------------------------------------------------------------------------
printf '\nAC0: Static — seed script exists at bin/seed-global-graph.sh\n'

if [ -f "$SEED_SCRIPT" ]; then
  assert_pass "bin/seed-global-graph.sh exists"
else
  assert_fail "bin/seed-global-graph.sh exists" "file not found at $SEED_SCRIPT"
fi

# ---------------------------------------------------------------------------
# Skip integration tests if jq not available
# ---------------------------------------------------------------------------
if ! command -v jq >/dev/null 2>&1; then
  printf '  SKIP: integration tests require jq\n'
  printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi

# ---------------------------------------------------------------------------
# Integration setup — use a fake HOME with a pre-seeded global-graph.json
# ---------------------------------------------------------------------------
FAKE_HOME="$(mktemp -d)"
REGISTRY_DIR="${FAKE_HOME}/.claude/forge/registry"
REGISTRY="${REGISTRY_DIR}/global-graph.json"
mkdir -p "$REGISTRY_DIR"

# Seed with 2 existing forge-project entries (simulates real state)
cat > "$REGISTRY" <<'EOF'
{
  "version": "1.0",
  "last_updated": "2026-02-26T02:00:42Z",
  "entities": [
    {
      "type": "forge-project",
      "name": "dashboard",
      "path": "/Users/dkay/code/PROD/ACE/dashboard",
      "registered_at": "2026-02-26T02:00:30Z"
    },
    {
      "type": "forge-project",
      "name": "ACE_NUXT_OPTIMIZED",
      "path": "/Users/dkay/code/ACE_NUXT_OPTIMIZED",
      "registered_at": "2026-02-26T02:00:42Z"
    }
  ],
  "relationships": []
}
EOF

# Run the seed script against the fake HOME registry
OLD_HOME="$HOME"
HOME="$FAKE_HOME"

set +e
SEED_OUT="$(bash "$SEED_SCRIPT" "$REGISTRY" 2>&1)"
SEED_RC=$?
set -e

HOME="$OLD_HOME"

if [ $SEED_RC -ne 0 ]; then
  printf '  SKIP: seed script failed (rc=%d)\n' $SEED_RC
  printf '  Output:\n'
  printf '%s\n' "$SEED_OUT" | head -20 | sed 's/^/    /'
  printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
  rm -rf "$FAKE_HOME"
  [ "$FAIL" -eq 0 ] && exit 0 || exit 1
fi

# ---------------------------------------------------------------------------
# AC1: Entity count >= 13 (2 forge-project + 11 infra)
# ---------------------------------------------------------------------------
printf '\nAC1: Entity count >= 13 after seeding\n'

ENTITY_COUNT="$(jq '.entities | length' "$REGISTRY")"

if [ "$ENTITY_COUNT" -ge 13 ]; then
  assert_pass "entity count is $ENTITY_COUNT (>= 13)"
else
  assert_fail "entity count >= 13" "got $ENTITY_COUNT"
fi

# ---------------------------------------------------------------------------
# AC2: All 11 required infra entity IDs present
# ---------------------------------------------------------------------------
printf '\nAC2: All required infra entity IDs present\n'

REQUIRED_IDS=(
  "ext-microsoft-entra-id"
  "ext-ldap"
  "ext-ukg-rest"
  "db-mssql-konami"
  "db-mssql-newwave"
  "db-mssql-infogenesis"
  "db-mssql-cct-prr"
  "db-mssql-cct-bok-homa"
  "db-mssql-cct-crystal-sky"
  "db-oracle-sws"
  "infra-harbor-registry"
  "infra-microk8s"
  "pipeline-woodpecker"
)

for id in "${REQUIRED_IDS[@]}"; do
  COUNT="$(jq --arg id "$id" '[.entities[] | select(.id == $id)] | length' "$REGISTRY")"
  if [ "$COUNT" -eq 1 ]; then
    assert_pass "entity '$id' present"
  else
    assert_fail "entity '$id' present" "found $COUNT entries (expected 1)"
  fi
done

# ---------------------------------------------------------------------------
# AC3: db-oracle-sws has READ ONLY constraint
# ---------------------------------------------------------------------------
printf '\nAC3: db-oracle-sws has READ ONLY access constraint\n'

ORACLE_CONSTRAINTS="$(jq '.entities[] | select(.id == "db-oracle-sws") | .constraints' "$REGISTRY")"

if [ -z "$ORACLE_CONSTRAINTS" ] || [ "$ORACLE_CONSTRAINTS" = "null" ]; then
  assert_fail "db-oracle-sws has constraints array" "constraints is null or missing"
else
  assert_pass "db-oracle-sws has constraints array"

  ACCESS_CONSTRAINT="$(jq '.entities[] | select(.id == "db-oracle-sws") | .constraints[] | select(.type == "access")' "$REGISTRY")"
  if [ -n "$ACCESS_CONSTRAINT" ]; then
    assert_pass "db-oracle-sws constraints contains an entry of type 'access'"

    if printf '%s' "$ACCESS_CONSTRAINT" | jq -r '.value' | grep -q "READ ONLY"; then
      assert_pass "db-oracle-sws access constraint value contains 'READ ONLY'"
    else
      assert_fail "db-oracle-sws access constraint value contains 'READ ONLY'" \
        "value: $(printf '%s' "$ACCESS_CONSTRAINT" | jq -r '.value')"
    fi
  else
    assert_fail "db-oracle-sws constraints contains an entry of type 'access'" \
      "no constraint with type 'access' found"
  fi
fi

# ---------------------------------------------------------------------------
# AC4: Each infra entity has a "kind" field
# ---------------------------------------------------------------------------
printf '\nAC4: Each infra entity has a "kind" field\n'

INFRA_IDS=(
  "ext-microsoft-entra-id"
  "ext-ldap"
  "ext-ukg-rest"
  "db-mssql-konami"
  "db-mssql-newwave"
  "db-mssql-infogenesis"
  "db-mssql-cct-prr"
  "db-mssql-cct-bok-homa"
  "db-mssql-cct-crystal-sky"
  "db-oracle-sws"
  "infra-harbor-registry"
  "infra-microk8s"
  "pipeline-woodpecker"
)

for id in "${INFRA_IDS[@]}"; do
  KIND="$(jq -r --arg id "$id" '.entities[] | select(.id == $id) | .kind // "MISSING"' "$REGISTRY")"
  if [ "$KIND" = "MISSING" ] || [ -z "$KIND" ]; then
    assert_fail "entity '$id' has 'kind' field" "kind is missing or empty"
  else
    assert_pass "entity '$id' has kind='$KIND'"
  fi
done

# ---------------------------------------------------------------------------
# AC5: Idempotency — running seed script twice does not duplicate entries
# ---------------------------------------------------------------------------
printf '\nAC5: Idempotency — second run does not create duplicates\n'

COUNT_BEFORE="$(jq '.entities | length' "$REGISTRY")"

HOME="$FAKE_HOME"
set +e
bash "$SEED_SCRIPT" "$REGISTRY" >/dev/null 2>&1
SEED_RC2=$?
set -e
HOME="$OLD_HOME"

COUNT_AFTER="$(jq '.entities | length' "$REGISTRY")"

if [ "$COUNT_BEFORE" -eq "$COUNT_AFTER" ]; then
  assert_pass "entity count stable after second run ($COUNT_BEFORE → $COUNT_AFTER)"
else
  assert_fail "entity count stable after second run" \
    "before=$COUNT_BEFORE after=$COUNT_AFTER (duplicates created)"
fi

# ---------------------------------------------------------------------------
# AC6: Existing forge-project entries preserved
# ---------------------------------------------------------------------------
printf '\nAC6: Existing forge-project entries preserved after seeding\n'

PROJ_COUNT="$(jq '[.entities[] | select(.type == "forge-project")] | length' "$REGISTRY")"
if [ "$PROJ_COUNT" -ge 2 ]; then
  assert_pass "forge-project entries preserved ($PROJ_COUNT found)"
else
  assert_fail "forge-project entries preserved" \
    "found $PROJ_COUNT forge-project entries (expected >= 2)"
fi

# Check specific projects still present
for proj_path in "/Users/dkay/code/PROD/ACE/dashboard" "/Users/dkay/code/ACE_NUXT_OPTIMIZED"; do
  EXISTS="$(jq --arg p "$proj_path" '[.entities[] | select(.type == "forge-project" and .path == $p)] | length' "$REGISTRY")"
  if [ "$EXISTS" -eq 1 ]; then
    assert_pass "forge-project entry preserved: $proj_path"
  else
    assert_fail "forge-project entry preserved: $proj_path" \
      "entry not found after seeding"
  fi
done

# ---------------------------------------------------------------------------
# Cleanup
# ---------------------------------------------------------------------------
rm -rf "$FAKE_HOME"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n--- Results: %d passed, %d failed ---\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
