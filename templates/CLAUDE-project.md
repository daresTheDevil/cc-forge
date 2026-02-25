# [Project Name] — CC-Forge Project Context
# .claude/CLAUDE.md
# Project-specific context. Global forge rules still apply — this extends them.
# TARGET: < 80 lines. If you need more, it belongs in agent_docs/.

## What This Project Is
[One paragraph. What it does, why it exists, who uses it. Be specific.]
Example: "Core API service powering the customer portal. Exposes 47 REST endpoints
consumed by the Nuxt frontend and 3 external partners. Owns the Customer, Order, and
Billing domains. Writes to SQL Server (primary) and publishes events to the message bus."

## Stack at a Glance
Runtime:    Node 20 / Python 3.12 / k8s namespace: [namespace]
Databases:  SQL Server (primary read/write) | Oracle (read-only legacy)
Frontend:   Nuxt 3 SSR | API: Express + OpenAPI 3.1
CI:         GitHub Actions | Deploy: Helm via ArgoCD
Auth:       JWT via shared auth service (see api-patterns.md)

## Key Commands
bun run dev          → start local dev server (port 3000)
bun run test         → run targeted tests (NEVER the full suite)
bun run test:watch   → watch mode for TDD
bun run typecheck    → TypeScript check (run after every significant change)
bun run lint         → Biome lint + format check
flyway migrate       → run pending DB migrations (staging only — never prod directly)
helm diff            → preview k8s changes before apply

## Where Things Live
src/routes/          → API route handlers (one file per domain)
src/services/        → business logic (no DB calls here — use repositories)
src/repositories/    → all DB access (SQL Server via mssql, Oracle via oracledb)
src/middleware/      → auth, validation, rate limiting, correlation ID
db/migrations/       → Flyway versioned migrations (V{n}__{description}.sql)
db/migrations/undo/  → rollback scripts (U{n}__{description}.sql — required)
deploy/helm/         → Helm chart and values files
.github/workflows/   → CI pipeline definitions
docs/api/            → OpenAPI spec (openapi.yaml — source of truth)

## Project-Specific Rules (extends global)
- Auth middleware is MANDATORY on every route. No exceptions. See api-patterns.md.
- Every new DB query on tables > 10k rows needs an execution plan in the PR.
- Legacy Oracle reads are read-only — do not attempt writes, the account lacks permission.
- The /health/* routes must never require auth — they're called by k8s probes.
- Correlation IDs must be propagated to every downstream call and log entry.

## What Claude Gets Wrong Here
- Do NOT import from `src/db` directly — all DB access goes through repositories.
- Do NOT use `res.json()` for errors — use the shared `ApiError` class (src/errors/).
- Do NOT write raw SQL in route handlers — belongs in repositories with parameterization.
- Flyway migration filenames are IMMUTABLE once merged — never rename them.
- The `legacy-oracle` db connection pool is shared — never close it explicitly.

## Agent Docs (read before starting — pick what's relevant)
agent_docs/architecture.md      → service map and upstream/downstream dependencies
agent_docs/database-schema.md   → key tables, migration history, naming conventions
agent_docs/api-patterns.md      → auth flow, error schema, versioning, rate limiting
agent_docs/k8s-layout.md        → namespace, deployments, ingress, secrets management
agent_docs/testing-guide.md     → what to test, how, coverage targets, CI gate order
agent_docs/runbooks/            → debugging production issues, common failure patterns
