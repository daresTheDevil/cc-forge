---
last_verified: YYYY-MM-DD
last_verified_by: [session-id or engineer-name]
drift_check: compare against db/migrations/ latest state — run flyway info and verify described tables match
---

# Database Schema Reference

> Template — populate during `/discuss` session or after running `/db-explorer`.
> Replace all `[FILL IN]` sections. Delete this instruction line when done.

## Connection Summary

| Database | Type | Schema/DB Name | Notes |
|----------|------|---------------|-------|
| [FILL IN] | SQL Server / Oracle | [FILL IN] | [FILL IN] |

**Connection strings:** Stored in `[FILL IN: env var name]`. Never hardcoded.
**Migration tool:** Flyway — `V{n}__{PascalCase}.sql` forward, `U{n}__{PascalCase}.sql` rollback.
**Current migration version:** [FILL IN: run `flyway info` to get this]

## Core Tables

[FILL IN: For each significant table:]

### `[table_name]`
**Purpose:** [one sentence — what business entity does this represent?]
**Estimated rows:** [FILL IN: `SELECT COUNT(*) FROM [table]`]

| Column | Type | Nullable | Notes |
|--------|------|----------|-------|
| `id` | INT IDENTITY | NO | Primary key |
| [FILL IN] | | | |

**Indexes:** [FILL IN: non-obvious indexes and why they exist]
**Foreign keys:** [FILL IN]
**Gotchas:** [FILL IN: things that look wrong but aren't, implicit assumptions, legacy quirks]

## Naming Conventions

[FILL IN: What naming conventions does this database follow?]
- Tables: [e.g., PascalCase, UPPER_SNAKE_CASE, prefixed with schema name]
- Columns: [e.g., snake_case, camelCase]
- Legacy fields: [FILL IN: if there are cryptic legacy column names, document translations here]

## Query Patterns

[FILL IN: Common query patterns used by the application. This helps Claude write correct queries.]

```sql
-- [Pattern name: e.g., "Get active sessions for a player"]
SELECT [columns] FROM [table]
WHERE [condition]
-- Notes: [why this query is written this way]
```

## Migration Safety Rules

- All migrations follow: `V{n}__{PascalCaseDescription}.sql`
- All migrations have a rollback: `U{n}__{PascalCaseDescription}.sql`
- Destructive operations (DROP, TRUNCATE, DELETE without WHERE) require `break_glass.destructive_migrations = true` in project.toml
- Test migrations against staging before production

## Known Performance Issues

[FILL IN: Tables with missing indexes, slow queries, things to watch out for]
