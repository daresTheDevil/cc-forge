---
last_verified: YYYY-MM-DD
last_verified_by: [session-id or engineer-name]
drift_check: compare against docs/api/openapi.yaml — verify endpoint list and response shapes match
---

# API Patterns and Conventions

> Template — populate during `/discuss` session.
> Replace all `[FILL IN]` sections. Delete this instruction line when done.

## API Overview

- **Type:** [REST / GraphQL / gRPC / mixed]
- **Base URL:** `[FILL IN: e.g., /api/v1]`
- **Spec:** `[FILL IN: docs/api/openapi.yaml or link]`
- **Auth mechanism:** [FILL IN: JWT Bearer / Session cookie / API key / mTLS]

## Authentication

[FILL IN: How do clients authenticate? What does the auth middleware look like?]

```typescript
// Example: How a route requires authentication
// [FILL IN: actual pattern used in this codebase]
router.get('/resource', requireAuth, async (req, res) => { ... })
```

**Token location:** [Header / Cookie / Both]
**Token refresh:** [How and when tokens are refreshed]
**Auth errors:** [What 401 vs 403 mean in this system]

## Standard Response Shape

[FILL IN: What does a successful response look like? What does an error look like?]

```json
// Success
{
  "data": { ... },
  "meta": { "page": 1, "total": 100 }
}

// Error (via shared ApiError class — NEVER raw res.json() for errors)
{
  "error": {
    "code": "RESOURCE_NOT_FOUND",
    "message": "Player not found",
    "correlationId": "req-abc-123"
  }
}
```

## Correlation IDs

[FILL IN: How are correlation IDs generated and propagated?]
- **Header name:** `[e.g., X-Correlation-ID]`
- **Generation:** [per-request in middleware, from upstream, etc.]
- **Logging:** [confirm they appear in all log lines]

## Input Validation

[FILL IN: What validation library/pattern is used?]
- Framework: [e.g., zod, joi, class-validator, manual]
- Location: [where validation happens — middleware, controller, service layer]
- Error format: [how validation errors are returned]

## Key Endpoints

[FILL IN: Document the most important/complex endpoints. For each:]

### `[METHOD] [path]`
**Purpose:** [one sentence]
**Auth required:** [yes/no, which roles]
**Request:** [key fields]
**Response:** [key fields]
**Notes:** [non-obvious behavior, rate limits, side effects]

## Common Patterns

[FILL IN: Patterns that appear throughout the codebase — copy these, don't invent new ones]

```typescript
// [Pattern name: e.g., "Paginated list endpoint"]
// [FILL IN: actual code pattern]
```

## Things That Will Bite You

[FILL IN: Non-obvious behaviors, legacy quirks, things that burned someone before]
