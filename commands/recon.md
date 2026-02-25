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

## Behavioral Imperatives

- Read-only except for writing to `.claude/forge/registry/project-graph.json` and `agent_docs/`.
- Do NOT read `.env`, `.env.production`, or any secrets file.
- Flag security issues found during recon with `[HALT][SEC]` — don't defer.
- Populate registry with what you observed, not what you inferred.

## Project/Scope: $ARGUMENTS
