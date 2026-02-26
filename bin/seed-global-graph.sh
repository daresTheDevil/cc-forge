#!/usr/bin/env bash
# bin/seed-global-graph.sh
# CC-Forge: Seed the global registry with known PRR shared infrastructure.
#
# Usage:
#   seed-global-graph.sh [REGISTRY_PATH]
#
# REGISTRY_PATH defaults to ~/.claude/forge/registry/global-graph.json
# Passing an explicit path is used by tests.
#
# This script is idempotent: entities are merged by id — existing entries are
# updated and no duplicates are created. Existing forge-project entries and
# any constraints on existing entities are preserved.

set -euo pipefail

REGISTRY="${1:-${HOME}/.claude/forge/registry/global-graph.json}"

if ! command -v jq >/dev/null 2>&1; then
  printf '[CC-Forge] ERROR: jq is required. Install: brew install jq\n' >&2
  exit 1
fi

if [ ! -f "$REGISTRY" ]; then
  printf '[CC-Forge] ERROR: Registry not found: %s\n' "$REGISTRY" >&2
  printf '[CC-Forge] Run cc-forge (global install) first.\n' >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# PRR Shared Infrastructure Entities
# Each entity has:
#   id        — stable, kebab-case identifier used for deduplication
#   kind      — entity classification (database | service | k8s_resource | pipeline_stage)
#   name      — human-readable name
#   type      — "infra" to distinguish from "forge-project" entries
#   + kind-specific fields (host, url, namespace, etc.)
#
# Oracle SWS carries a first-class READ ONLY constraint — this is an account-level
# database restriction, not a code guard. Never silently drop this on merge.
# ---------------------------------------------------------------------------

INFRA_ENTITIES='[
  {
    "id": "ext-microsoft-entra-id",
    "type": "infra",
    "kind": "service",
    "name": "Microsoft Entra ID",
    "description": "Primary authentication and identity provider for all PRR apps (Azure AD / OIDC / OAuth2)"
  },
  {
    "id": "ext-ldap",
    "type": "infra",
    "kind": "service",
    "name": "LDAP",
    "description": "Authentication fallback and employee directory service"
  },
  {
    "id": "ext-ukg-rest",
    "type": "infra",
    "kind": "service",
    "name": "UKG REST API",
    "description": "HR system of record — employee data, org structure, scheduling"
  },
  {
    "id": "db-mssql-konami",
    "type": "infra",
    "kind": "database",
    "name": "Konami Synkros (MSSQL)",
    "description": "Slot management and banned patron database — Konami Synkros system"
  },
  {
    "id": "db-mssql-newwave",
    "type": "infra",
    "kind": "database",
    "name": "NewWave Gaming (MSSQL)",
    "description": "Casino CMS patron data — NewWave Gaming system"
  },
  {
    "id": "db-mssql-infogenesis",
    "type": "infra",
    "kind": "database",
    "name": "InfoGenesis F&B POS (MSSQL)",
    "description": "Food and beverage point-of-sale system at 172.30.120.10"
  },
  {
    "id": "db-mssql-cct-prr",
    "type": "infra",
    "kind": "database",
    "name": "CCT PRR (MSSQL)",
    "description": "CCT database for Pearl River Resort property"
  },
  {
    "id": "db-mssql-cct-bok-homa",
    "type": "infra",
    "kind": "database",
    "name": "CCT Bok Homa (MSSQL)",
    "description": "CCT database for Bok Homa Casino property"
  },
  {
    "id": "db-mssql-cct-crystal-sky",
    "type": "infra",
    "kind": "database",
    "name": "CCT Crystal Sky (MSSQL)",
    "description": "CCT database for Crystal Sky at Choctaw property"
  },
  {
    "id": "db-oracle-sws",
    "type": "infra",
    "kind": "database",
    "name": "Oracle SWS/Silver",
    "description": "Oracle SWS Silver database. Account-level READ ONLY restriction — no write possible at runtime.",
    "constraints": [
      {
        "type": "access",
        "value": "READ ONLY — account-level restriction, no write possible at runtime"
      }
    ]
  },
  {
    "id": "infra-harbor-registry",
    "type": "infra",
    "kind": "k8s_resource",
    "name": "Harbor Container Registry",
    "host": "harbor.dev.pearlriverresort.com",
    "description": "Private container registry for all PRR projects"
  },
  {
    "id": "infra-microk8s",
    "type": "infra",
    "kind": "k8s_resource",
    "name": "MicroK8s Cluster",
    "namespace_convention": "prr-*",
    "description": "On-premises MicroK8s cluster. Namespace convention: prr-*. Use microk8s kubectl, never bare kubectl."
  },
  {
    "id": "pipeline-woodpecker",
    "type": "infra",
    "kind": "pipeline_stage",
    "name": "Woodpecker CI",
    "description": "Org-standard CI/CD pipeline (not GitHub Actions). Used for all PRR projects."
  }
]'

# ---------------------------------------------------------------------------
# Merge infra entities into the registry.
# Strategy per entity:
#   - If no entity with this id exists: append it.
#   - If entity with same id exists: merge, preserving any existing constraints.
# ---------------------------------------------------------------------------
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

UPDATED="$(jq \
  --argjson infra "$INFRA_ENTITIES" \
  --arg ts "$TIMESTAMP" '
  # For each incoming infra entity, merge into the existing entities array.
  # Deduplication key: .id
  # Constraint preservation: if existing entity has constraints, they are
  # kept and merged with any new constraints (union by .type).
  reduce $infra[] as $new_entity (
    .;
    . as $doc |
    ($new_entity.id) as $id |
    if ([ $doc.entities[] | select(.id == $id) ] | length) > 0
    then
      # Entity exists — merge, preserving existing constraints
      .entities = [
        $doc.entities[] |
        if .id == $id then
          # Merge: start with new entity fields, overlay with preserved constraints
          ($new_entity +
            (if (.constraints // null) != null
             then
               # Merge constraints: union by .type, preserving existing values
               { "constraints": (
                   (($new_entity.constraints // []) + (.constraints // [])) |
                   unique_by(.type)
                 )
               }
             else {}
             end
            )
          )
        else
          .
        end
      ]
    else
      # Entity does not exist — append
      .entities = (.entities + [$new_entity])
    end
  ) |
  .last_updated = $ts
' "$REGISTRY")"

printf '%s' "$UPDATED" > "$REGISTRY"

ENTITY_COUNT="$(jq '.entities | length' "$REGISTRY")"
INFRA_COUNT="$(jq '[.entities[] | select(.type == "infra")] | length' "$REGISTRY")"

printf '[CC-Forge] Global graph seeded: %d total entities (%d infra)\n' \
  "$ENTITY_COUNT" "$INFRA_COUNT"
printf '[CC-Forge] Registry: %s\n' "$REGISTRY"
