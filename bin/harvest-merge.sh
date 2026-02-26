#!/usr/bin/env bash
# bin/harvest-merge.sh
# CC-Forge: Merge a single harvested entity into the global graph with conflict detection.
#
# Usage:
#   harvest-merge.sh <registry-path> <entity-json>
#
# Arguments:
#   registry-path   Absolute path to global-graph.json
#   entity-json     A JSON string representing the candidate entity to merge
#
# Exit codes:
#   0   Success — entity was either skipped (identical) or appended (new)
#   1   Error — invalid arguments, missing jq, registry not found, or JSON parse failure
#   2   Conflict — entity with same id exists but has different metadata;
#                  registry is NOT modified; caller must resolve
#
# Conflict rules (per plan T010):
#   Same id, same data            → skip, exit 0 (already current)
#   Same id, different metadata   → exit 2 (human review required, no silent overwrite)
#   Same id, existing constraints → constraints always preserved, never dropped on merge
#   New entity (no id match)      → append, exit 0
#
# This script is called by the recon harvest pass and can be called directly
# by tests. It is NOT interactive — conflict resolution happens in the caller
# (Claude, in interactive recon mode).

set -euo pipefail

# ---------------------------------------------------------------------------
# Argument validation
# ---------------------------------------------------------------------------
if [ $# -ne 2 ]; then
  printf '[harvest-merge] ERROR: Usage: harvest-merge.sh <registry-path> <entity-json>\n' >&2
  exit 1
fi

REGISTRY="$1"
CANDIDATE_JSON="$2"

if ! command -v jq >/dev/null 2>&1; then
  printf '[harvest-merge] ERROR: jq is required. Install: brew install jq\n' >&2
  exit 1
fi

if [ ! -f "$REGISTRY" ]; then
  printf '[harvest-merge] ERROR: Registry not found: %s\n' "$REGISTRY" >&2
  exit 1
fi

# Validate candidate JSON is parseable and has an id
CANDIDATE_ID="$(printf '%s' "$CANDIDATE_JSON" | jq -r '.id // empty' 2>/dev/null || true)"
if [ -z "$CANDIDATE_ID" ]; then
  printf '[harvest-merge] ERROR: candidate entity JSON is invalid or missing .id\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Check for existing entity with same id
# ---------------------------------------------------------------------------
EXISTING_COUNT="$(jq --arg id "$CANDIDATE_ID" '[.entities[] | select(.id == $id)] | length' "$REGISTRY")"

if [ "$EXISTING_COUNT" -eq 0 ]; then
  # -------------------------------------------------------------------------
  # New entity — append cleanly
  # -------------------------------------------------------------------------
  TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  UPDATED="$(jq \
    --argjson candidate "$(printf '%s' "$CANDIDATE_JSON")" \
    --arg ts "$TIMESTAMP" '
    .entities = (.entities + [$candidate]) |
    .last_updated = $ts
  ' "$REGISTRY")"
  printf '%s' "$UPDATED" > "$REGISTRY"
  printf '[harvest-merge] Appended new entity: %s\n' "$CANDIDATE_ID"
  exit 0
fi

# ---------------------------------------------------------------------------
# Entity with same id exists — compare
# ---------------------------------------------------------------------------

# Extract the existing entity
EXISTING_JSON="$(jq --arg id "$CANDIDATE_ID" '.entities[] | select(.id == $id)' "$REGISTRY")"

# Constraint preservation: if the existing entity has constraints, they must
# survive regardless of the candidate. Build the "safe candidate" which is
# the candidate with the existing constraints overlaid.
#
# We compare the candidate WITH preserved constraints against existing to
# determine if there is a real conflict beyond just constraints.
EXISTING_HAS_CONSTRAINTS="$(printf '%s' "$EXISTING_JSON" | jq '(.constraints // null) != null and (.constraints | length) > 0')"

if [ "$EXISTING_HAS_CONSTRAINTS" = "true" ]; then
  # Merge constraints: union of existing + candidate constraints, by .type
  # Existing constraint values always win (never silently overwritten)
  SAFE_CANDIDATE="$(jq -n \
    --argjson existing "$EXISTING_JSON" \
    --argjson candidate "$(printf '%s' "$CANDIDATE_JSON")" '
    $candidate +
    {
      "constraints": (
        (($candidate.constraints // []) + ($existing.constraints // [])) |
        unique_by(.type)
      )
    }
  ')"
else
  SAFE_CANDIDATE="$CANDIDATE_JSON"
fi

# Compare safe candidate (with preserved constraints) against existing entity.
# Normalize both to sorted, compact JSON for deterministic comparison.
EXISTING_NORMALIZED="$(printf '%s' "$EXISTING_JSON" | jq -Sc 'to_entries | sort_by(.key) | from_entries')"
SAFE_NORMALIZED="$(printf '%s' "$SAFE_CANDIDATE" | jq -Sc 'to_entries | sort_by(.key) | from_entries')"

if [ "$EXISTING_NORMALIZED" = "$SAFE_NORMALIZED" ]; then
  # -------------------------------------------------------------------------
  # Identical (accounting for constraint preservation) — skip
  # -------------------------------------------------------------------------
  printf '[harvest-merge] Skip (already current): %s\n' "$CANDIDATE_ID"
  exit 0
fi

# -------------------------------------------------------------------------
# Conflict: same id, different metadata — do NOT silently modify registry
# -------------------------------------------------------------------------
printf '[harvest-merge] CONFLICT: entity "%s" exists with different metadata.\n' "$CANDIDATE_ID" >&2
printf '[harvest-merge] Existing:\n%s\n' "$(printf '%s' "$EXISTING_JSON" | jq -C '.')" >&2
printf '[harvest-merge] Candidate:\n%s\n' "$(printf '%s' "$SAFE_CANDIDATE" | jq -C '.')" >&2
printf '[harvest-merge] Registry NOT modified. Resolve conflict and re-run, or accept existing.\n' >&2
exit 2
