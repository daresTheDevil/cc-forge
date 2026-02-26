---
description: Analyze blast radius of a proposed change across the registered codebase. Reads project-graph.json to map all entities and relationships that would be affected. Use before any significant refactor, API change, or cross-service change.
allowed-tools: Bash, Read, Grep, Glob
---

# CC-Forge: BLAST RADIUS

You are analyzing the blast radius of a proposed change. Your job is to find what breaks, what slows down, and what needs to change before the developer touches anything.

Be thorough. Be paranoid. The developer is relying on you to catch what they didn't think of.

---

## Step 1: Read the Coherence Registry

Read `.claude/forge/registry/project-graph.json`.

If the registry is empty or non-existent, skip to Step 3 and note that the registry needs to be populated via `/forge--recon`. Proceed with file-level analysis using the global graph if available.

Also read `~/.claude/forge/registry/global-graph.json` (the global registry).

If the global graph is absent or empty, note it and continue — it is not an error. If the global graph is present, identify any entities in it that match the change subject (match on `id` or `name`).

Use the global graph to enumerate which other registered projects may be affected:
- Find `forge-project` entries in the global graph — these are all registered repos.
- For each matched shared entity (database, external service, pipeline, infra), check which registered projects use it by scanning their project-level graphs (`.claude/forge/registry/project-graph.json` in each registered project path).

Identify:
- All entities related to the change subject (direct + 1-hop relationships)
- Relationship types: `reads-from`, `writes-to`, `depends-on`, `authenticates-via`, `deployed-by`, `tested-by`

---

## Step 2: Map Impact Rings

**Ring 0 — Epicenter:** The entity/file/service being directly changed.

**Ring 1 — Direct dependencies:**
- Entities that `depends-on` the epicenter
- Entities the epicenter `depends-on`
- Consumers of any changed API contract (check openapi.yaml for API changes)

**Ring 2 — Indirect dependencies:**
- Services that call Ring 1 services
- Tests that cover Ring 0 and Ring 1 entities
- CI/CD pipelines that build or deploy affected services
- k8s deployments that consume affected services

**Ring 3 — Soft dependencies:**
- Documentation that describes affected behavior (agent_docs/, README, API docs)
- Monitoring/alerting that references affected endpoints or metrics
- Feature flags that control affected code paths

---

## Step 2b: Cross-Project Impact (Global Graph)

If the global graph (`~/.claude/forge/registry/global-graph.json`) is present and the change subject matches a shared entity (a `database`, external `service`, `pipeline_stage`, or cluster-level `k8s_resource`), surface the cross-project blast radius:

1. List all `forge-project` entries in the global graph — these are all registered repos.
2. For each registered project path that exists on disk, check its `.claude/forge/registry/project-graph.json` for relationships to the affected entity.
3. Report which other registered projects reference the same shared entity.

Example:

```bash
GLOBAL="${HOME}/.claude/forge/registry/global-graph.json"
ENTITY_ID="db-oracle-sws"

# List registered project paths
jq -r '.entities[] | select(.type == "forge-project") | .path' "$GLOBAL"

# Check each project's graph for the entity
for project_path in $(jq -r '.entities[] | select(.type == "forge-project") | .path' "$GLOBAL"); do
  graph="${project_path}/.claude/forge/registry/project-graph.json"
  if [ -f "$graph" ]; then
    match=$(jq -r --arg id "$ENTITY_ID" '.entities[] | select(.id == $id) | .id' "$graph" 2>/dev/null || true)
    [ -n "$match" ] && echo "AFFECTED: $project_path"
  fi
done
```

Report format:

```
## Cross-Project Impact
Shared entity: [entity id / name]

Registered projects that reference this entity:
  [REVIEW] /path/to/project-a — references db-oracle-sws
  [AUTO]   /path/to/project-b — no reference found

Projects NOT found on disk (stale registry entries):
  /path/to/old-project — directory does not exist
```

If no registered projects are found, or the global graph is absent, state this explicitly and continue.

---

## Step 3: File-Level Impact Analysis

For each entity in Ring 0 and Ring 1, search the codebase:

```bash
# Find all imports/references to the changed entity
grep -r "[entity name or function]" --include="*.ts" --include="*.js" --include="*.py" --include="*.php" -l

# Find all usages of a changed API endpoint
grep -r "[endpoint path]" --include="*.ts" --include="*.js" -l

# Find all SQL queries against a changed table
grep -r "[table name]" --include="*.sql" --include="*.ts" --include="*.py" -l

# Find all k8s resources referencing a changed service
grep -r "[service name]" deploy/ -l 2>/dev/null || true
```

---

## Step 4: Grade the Impact

Grade each affected entity:

```
[AUTO]   — Change is safe to apply, no manual coordination needed
[REVIEW] — Change affects this entity, developer should verify before shipping
[HALT]   — Change BREAKS this entity, must be addressed before deployment
```

---

## Step 5: Generate Blast Radius Report

Output a structured report:

```markdown
# Blast Radius Report: [Change Description]

Analyzed: YYYY-MM-DD HH:MM
Registry entities checked: [N]

## Epicenter
[what is being changed]

## Impact Summary
| Ring | Count | Max Grade |
|------|-------|-----------|
| Ring 0 (epicenter) | 1 | - |
| Ring 1 (direct) | N | [HALT/REVIEW/AUTO] |
| Ring 2 (indirect) | N | [REVIEW/AUTO] |
| Ring 3 (soft) | N | [AUTO] |

## [HALT] — Must Fix Before Shipping
[list with file:line and what breaks]

## [REVIEW] — Verify Before Shipping
[list with file:line and what to check]

## [AUTO] — Safe to Ship
[summary count — no need to list every file]

## Required Updates (action list for BUILD mode)
- [ ] [file/entity]: [what needs to change]

## What's NOT affected
[explicitly state what was considered and found safe — builds confidence]
```

---

## Behavioral Imperatives

- Do NOT make changes during blast radius analysis — this is read-only.
- State explicit `[HALT]` findings before anything else.
- Empty registries are not errors — note and proceed with file-level analysis.
- Err on the side of over-reporting: a false positive costs a review; a false negative costs a production incident.

## Change Description: $ARGUMENTS
