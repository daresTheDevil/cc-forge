---
last_verified: YYYY-MM-DD
last_verified_by: [session-id or engineer-name]
drift_check: compare against .claude/forge/registry/project-graph.json entities
---

# Architecture Overview

> Template — populate during `/discuss` session when first installing CC-Forge on this project.
> Replace all `[FILL IN]` sections. Delete this instruction line when done.

## System Purpose

[FILL IN: One paragraph. What does this system do? Who uses it? What problem does it solve?]

## Stack Summary

| Layer | Technology | Notes |
|-------|-----------|-------|
| Frontend | [e.g., Nuxt 3, TypeScript strict] | [FILL IN] |
| Backend API | [e.g., Node/Express, Python FastAPI] | [FILL IN] |
| Legacy | [e.g., PHP 7.4, no framework] | [FILL IN] |
| Databases | [e.g., SQL Server 2019, Oracle 19c] | [FILL IN] |
| Infrastructure | [e.g., microk8s on Ubuntu 22.04] | [FILL IN] |
| CI/CD | [e.g., GitHub Actions] | [FILL IN] |

## Service Map

[FILL IN: List each service/application in the system. For each:]

### [Service Name]
- **Path:** `[repo path or git repo URL]`
- **Purpose:** [one sentence]
- **Port:** [internal port]
- **Dependencies:** [other services, databases it calls]
- **Deployment:** [how it runs — k8s deployment, bare process, etc.]

## Data Flow

[FILL IN: Describe the main request paths through the system. A simple text diagram is fine:]

```
User → [Frontend] → [API Gateway] → [Auth Service] → [Business Service] → [Database]
```

## Key Boundaries

[FILL IN: What are the critical integration points? Where do things fail?]
- **External dependencies:** [third-party APIs, payment gateways, etc.]
- **Synchronous vs async:** [which calls are sync, which are queued]
- **Failure modes:** [what happens when [service X] is down?]

## Non-Obvious Decisions

[FILL IN: Things that look wrong but aren't. Things that look right but are wrong. Gotchas that burned someone.]

## Out of Scope (intentionally)

[FILL IN: What is explicitly NOT handled by this system?]
