# SQL Server (MSSQL) Database Skill
# ~/.claude/forge/skills/databases/mssql.md
# Load this skill before working with SQL Server databases.

## Stack Context

- SQL Server accessed via `mssql` npm package (Node.js) or `pyodbc`/`pymssql` (Python)
- Schema migrations managed by Flyway: `V{n}__{Description}.sql` + `U{n}__{Description}.sql`
- Credentials from env vars or k8s secrets — never hardcoded
- `sqlcmd` is available for CLI operations (requires operator confirmation in Forge)

## Credentials

```
MSSQL_HOST      — server hostname or IP
MSSQL_PORT      — port (default: 1433)
MSSQL_DATABASE  — database name
MSSQL_USER      — service account
MSSQL_PASSWORD  — password (from k8s secret or .env, never committed)
MSSQL_ENCRYPT   — true for production, false for local dev
```

Read connection config from `project.toml` `[stack.databases.mssql]` if present.

## Connection Patterns

### Node.js (mssql package)

```typescript
import sql from 'mssql'

const pool = await sql.connect({
  server:   process.env.MSSQL_HOST!,
  port:     parseInt(process.env.MSSQL_PORT ?? '1433'),
  database: process.env.MSSQL_DATABASE!,
  user:     process.env.MSSQL_USER!,
  password: process.env.MSSQL_PASSWORD!,
  options: {
    encrypt:                process.env.MSSQL_ENCRYPT !== 'false',
    trustServerCertificate: process.env.NODE_ENV !== 'production',
    enableArithAbort:       true,
  },
  pool: {
    max:              10,
    min:              2,
    idleTimeoutMillis: 30000,
  },
})

// Always parameterized — never string concatenation
export async function query<T = unknown>(
  queryStr: string,
  params: Record<string, { type: sql.ISqlType; value: unknown }>
): Promise<sql.IRecordSet<T>> {
  const request = pool.request()
  for (const [name, { type, value }] of Object.entries(params)) {
    request.input(name, type, value)
  }
  const result = await request.query<T>(queryStr)
  return result.recordset
}
```

### Python (pyodbc)

```python
import pyodbc
import os

connection_string = (
    f"DRIVER={{ODBC Driver 18 for SQL Server}};"
    f"SERVER={os.environ['MSSQL_HOST']},{os.environ.get('MSSQL_PORT', '1433')};"
    f"DATABASE={os.environ['MSSQL_DATABASE']};"
    f"UID={os.environ['MSSQL_USER']};"
    f"PWD={os.environ['MSSQL_PASSWORD']};"
    f"Encrypt={'yes' if os.environ.get('MSSQL_ENCRYPT', 'true') != 'false' else 'no'};"
    "TrustServerCertificate=no;"
)

conn = pyodbc.connect(connection_string)

# Always use parameterized queries — ? placeholder
cursor = conn.cursor()
cursor.execute(
    "SELECT player_id, first_name, last_name FROM dbo.Players WHERE player_id = ?",
    (player_id,)
)
```

## T-SQL Dialect — Key Differences

### Pagination (not LIMIT/OFFSET)

```sql
-- SQL Server pagination — ORDER BY is REQUIRED with OFFSET/FETCH
SELECT player_id, first_name, last_name
FROM dbo.Players
ORDER BY last_name, first_name
OFFSET 20 ROWS
FETCH NEXT 10 ROWS ONLY

-- Older SQL Server (pre-2012): use ROW_NUMBER()
SELECT * FROM (
  SELECT *, ROW_NUMBER() OVER (ORDER BY last_name) AS rn
  FROM dbo.Players
) t
WHERE rn BETWEEN 21 AND 30
```

### Date/time functions (not NOW(), not CURRENT_TIMESTAMP for most uses)

```sql
GETDATE()           -- current datetime (local)
GETUTCDATE()        -- current datetime (UTC) — prefer this
SYSDATETIMEOFFSET() -- current datetime with timezone offset
DATEADD(day, -7, GETUTCDATE())  -- 7 days ago
DATEDIFF(day, start_date, end_date)  -- difference in days
FORMAT(created_at, 'yyyy-MM-dd')  -- format as string
```

### TOP instead of LIMIT (for quick testing)

```sql
-- Quick test/debug — always scope first
SELECT TOP 10 * FROM dbo.Players ORDER BY created_at DESC
```

### String functions

```sql
LEN(str)         -- length (excludes trailing spaces)
DATALENGTH(str)  -- byte length (includes trailing spaces)
LTRIM(RTRIM(str)) -- trim (no single TRIM() in older versions)
TRIM(str)        -- SQL Server 2017+
CHARINDEX('x', str) -- find substring (1-indexed, 0 = not found)
SUBSTRING(str, 1, 10) -- substr (1-indexed)
CONCAT(a, b)     -- safe concatenation (handles NULLs)
```

### NULL handling

```sql
ISNULL(column, default_value)  -- replace NULL with default
COALESCE(a, b, c)              -- first non-NULL
NULLIF(a, b)                   -- return NULL if a = b
```

## Flyway Migrations

All schema changes go through Flyway. Naming conventions are strict.

```
db/migrations/
  V1__Initial_schema.sql
  V2__Add_player_sessions.sql
  V3__Add_session_index.sql
  U3__Remove_session_index.sql    ← undo for V3 only (not always required)
```

Rules:
- Version numbers are integers, sequential, never reused
- Double underscore between version and description (Flyway requirement)
- Description uses underscores, no spaces
- NEVER edit a migration that has already run in any environment
- Rollback = a new `U{n}__` migration, NOT a modified `V{n}__` migration
- All migrations must be idempotent where possible (`IF NOT EXISTS`, etc.)
- Never use `DROP` in a rollback — use rename/disable patterns

### Migration Template

```sql
-- V7__Add_session_timeout.sql
-- Adds timeout column to player_sessions with safe default

ALTER TABLE dbo.player_sessions
ADD timeout_at DATETIME2 NULL;

-- Backfill existing rows (30 minute default)
UPDATE dbo.player_sessions
SET timeout_at = DATEADD(minute, 30, started_at)
WHERE timeout_at IS NULL AND ended_at IS NULL;
```

```sql
-- U7__Remove_session_timeout.sql
-- Reversal for V7 — removes timeout column

ALTER TABLE dbo.player_sessions
DROP COLUMN timeout_at;
```

## Transactions

```typescript
// Always use transactions for multi-statement operations
const transaction = new sql.Transaction(pool)
await transaction.begin()
try {
  const request = new sql.Request(transaction)
  await request.query('UPDATE ...')
  await request.query('INSERT ...')
  await transaction.commit()
} catch (err) {
  await transaction.rollback()
  throw err
}
```

## Performance Patterns

- Add indexes via Flyway migrations — never manually on production
- Check execution plans for queries on large tables before deploying
- Use `SET NOCOUNT ON` in stored procedures to suppress row-count messages
- Avoid `SELECT *` — name columns explicitly in production code
- For large result sets: use streaming, not loading all rows into memory

## What to Always Avoid

- String concatenation in SQL: `"SELECT * FROM Users WHERE name = '" + name + "'"` → SQL injection
- Hardcoded credentials anywhere
- Editing already-run migration files
- `DROP TABLE` / `DROP COLUMN` in forward migrations (use deprecation pattern instead)
- `SELECT *` in production application code
