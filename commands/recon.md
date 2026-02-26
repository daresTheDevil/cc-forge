---
description: Rapid orientation scan for a new project or codebase. Produces a structured situation report and populates project-graph.json. Run this first when starting work on any new project.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob
---

# CC-Forge: RECON — Rapid Codebase Orientation

You are orienting yourself to this codebase. Your job is to build accurate situational awareness fast, then write it down so you and future sessions don't have to rediscover it.

Output: Populated `project-graph.json` + updated `agent_docs/` stubs + summary report.

---

## Phase 1: Stack Fingerprinting (5 minutes)

Run these scans to identify the stack. Don't read every file — scan for structure.

```bash
# Package manager and runtime
ls -la package.json composer.json requirements.txt Pipfile pyproject.toml Cargo.toml go.mod 2>/dev/null
cat package.json 2>/dev/null | jq '{name, description, scripts, dependencies}' 2>/dev/null || true

# Framework detection
grep -r "nuxt\|next\|express\|fastapi\|flask\|django\|laravel\|symfony" package.json requirements.txt composer.json 2>/dev/null | head -5

# Database detection
grep -rE "sqlserver|mssql|oracle|postgres|mysql|mongodb|redis|sqlite" \
  package.json requirements.txt composer.json .env.example 2>/dev/null | head -10

# Infrastructure
ls -la deploy/ k8s/ kubernetes/ docker-compose.yml Dockerfile 2>/dev/null
ls -la .claude/forge/project.toml 2>/dev/null

# Migration files
ls db/migrations/ 2>/dev/null | head -5 || true
ls -la flyway.conf 2>/dev/null || true
```

---

## Phase 2: Entry Point Discovery

Find where execution starts. This is the skeleton key to understanding everything else.

```bash
# Web entry points
find . -name "index.php" -o -name "app.ts" -o -name "server.ts" -o -name "main.py" \
  -o -name "app.py" -o -name "main.go" 2>/dev/null | grep -v node_modules | grep -v vendor

# Service entry points (k8s)
grep -r "command:\|args:" deploy/ k8s/ 2>/dev/null | head -10

# Script entry points
cat package.json 2>/dev/null | jq '.scripts' 2>/dev/null || true
```

---

## Phase 3: Service Inventory

List every deployable service in this repo.

```bash
# Kubernetes deployments
microk8s kubectl get deployments --all-namespaces 2>/dev/null | grep -v "NAMESPACE" || true

# Helm releases
helm list --all-namespaces 2>/dev/null || true

# Docker services
cat docker-compose.yml 2>/dev/null | grep -E "^  [a-z]" | head -20 || true

# Microservices layout
ls -la services/ apps/ packages/ 2>/dev/null || true
```

---

## Phase 4: Database Mapping

Identify every database and its purpose.

```bash
# Migration state
flyway info 2>/dev/null || true

# Connection configs (no credentials — just names and types)
grep -rE "(host|server|database|schema).*=" .env.example config/ 2>/dev/null | grep -v password | head -20

# Table count estimate
find db/migrations/ -name "V*.sql" 2>/dev/null | wc -l
```

---

## Phase 5: Security Posture Quick Check

```bash
# Secret scanner status
command -v git-secrets >/dev/null 2>&1 && echo "git-secrets: installed" || echo "git-secrets: MISSING"
command -v trufflehog >/dev/null 2>&1 && echo "trufflehog: installed" || echo "trufflehog: MISSING"

# Dependency audit
npm audit --json 2>/dev/null | jq '.metadata.vulnerabilities' 2>/dev/null || \
  bun audit 2>/dev/null | tail -5 || true
composer audit --no-ansi 2>/dev/null | tail -5 || true
pip3 audit 2>/dev/null | tail -5 || true

# Env files (check for .env tracked in git — critical)
git ls-files | grep -E "^\.env$|^\.env\." | head -5 && echo "WARNING: env files tracked in git!" || true
```

---

## Phase 6: Write Artifacts

### 6a: Populate project-graph.json

Write entities for each discovered service/database/major component to `.claude/forge/registry/project-graph.json`.

Entity shapes:
```json
{
  "id": "[unique-slug]",
  "kind": "service | database | k8s_resource | api_endpoint | ui_component | secret | pipeline_stage",
  "name": "[Human Name]",
  "path": "[path in repo or external URL]",
  "metadata": {}
}
```

### 6b: Update agent_docs/ stubs

For each discovered domain, update the `last_verified` date and fill in any obviously available information in the agent_docs/ templates. Don't write fiction — only write what you observed directly.

### 6c: Summary Report

Output a SITREP to the terminal:

```
CC-Forge RECON — [Project Name]
================================
Stack:       [summary]
Services:    [count] ([list])
Databases:   [count] ([list])
Migrations:  [count]
k8s:         [yes/no — namespace count]
Test suite:  [framework and command]
CI/CD:       [GitHub Actions / GitLab CI / none]

Security:
  Secret scanner: [installed/MISSING]
  Open vulns (npm): [count critical/high]
  Env in git: [yes=BAD / no=OK]

Registry populated: [entity count] entities
agent_docs/ updated: [which files touched]

Recommended first tasks:
1. [FILL IN: most important thing to address based on what you found]
2. [FILL IN]
```

---

---

## Phase 7: Harvest Pass — Promote Global Entities

After writing `project-graph.json`, run a harvest pass to promote globally-relevant
entities into `~/.claude/forge/registry/global-graph.json`.

### 7a: Classify entities from the project graph

Review every entity in `.claude/forge/registry/project-graph.json` and classify:

| Entity Kind | Disposition |
|---|---|
| `database` | Global candidate (shared infrastructure) |
| `service` (external — auth providers, HR systems, REST APIs) | Global candidate |
| `pipeline_stage` | Global candidate (org-wide CI/CD) |
| `k8s_resource` (cluster-level, e.g. Harbor, cluster itself) | Global candidate |
| `service` (the app itself) | Project-only — do NOT harvest |
| `api_endpoint` | Project-only — do NOT harvest |
| `ui_component` | Project-only — do NOT harvest |

### 7b: Conflict detection — run before writing anything

For each global candidate, call `bin/harvest-merge.sh` (or apply the same logic
interactively). The rules are strict:

**Rule 1 — Identical:** Same `id`, same data → skip silently. Already current.

**Rule 2 — Conflict:** Same `id`, different metadata → DO NOT silently overwrite.
Show a diff to the user and ask which version wins. Only write after explicit confirmation.

```
CONFLICT: entity "db-mssql-konami" exists with different metadata.

Existing (in global graph):
  name: "Konami Synkros (MSSQL)"
  description: "Slot management database"

Candidate (from this project graph):
  name: "Konami Synkros"
  description: "Slot management and banned patron database — Konami Synkros system"

Which version wins? [existing / candidate / skip]
```

**Rule 3 — Constraint preservation (non-negotiable):**
If an existing entity in the global graph has a `constraints` array, those constraints
MUST be preserved on any merge. Never silently drop constraints — only add new ones.
This is especially critical for `db-oracle-sws` (READ ONLY account-level restriction).

```json
{
  "id": "db-oracle-sws",
  "constraints": [
    {
      "type": "access",
      "value": "READ ONLY — account-level restriction, no write possible at runtime"
    }
  ]
}
```

**Rule 4 — New entity:** No existing entity with this `id` → append cleanly.

### 7c: Proposed harvest diff

After classifying and checking for conflicts, output a proposed diff:

```
CC-Forge HARVEST — proposed additions to global-graph.json
===========================================================
NEW  (will append):
  + db-mssql-konami     Konami Synkros (MSSQL)
  + ext-ukg-rest        UKG REST API

CONFLICTS (require your decision):
  ~ db-oracle-sws       name differs — see diff above

SKIP (already current):
  = infra-microk8s      MicroK8s Cluster

Proceed? [y/n/review]
```

Only write to `global-graph.json` after the user confirms.

### 7d: Use harvest-merge.sh for non-interactive scripting

When running in headless or scripted mode, call:

```bash
bash "$(npm prefix -g)/lib/node_modules/cc-forge/bin/harvest-merge.sh" \
  "${HOME}/.claude/forge/registry/global-graph.json" \
  "$ENTITY_JSON"
```

Exit codes: `0` = success (skipped or appended), `1` = error, `2` = conflict (halt, do not proceed).

---

## Behavioral Imperatives

- Read-only except for writing to `.claude/forge/registry/project-graph.json`,
  `agent_docs/`, and `~/.claude/forge/registry/global-graph.json` (harvest, confirmed only).
- Do NOT read `.env`, `.env.production`, or any secrets file.
- Flag security issues found during recon with `[HALT][SEC]` — don't defer.
- Populate registry with what you observed, not what you inferred.
- Never silently overwrite global-graph entities — always show conflicts and ask.

## Project/Scope: $ARGUMENTS
