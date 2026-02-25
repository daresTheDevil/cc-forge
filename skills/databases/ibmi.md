# IBM i (AS/400 / iSeries) Database Skill
# ~/.claude/forge/skills/databases/ibmi.md
# Load this skill before working with IBM i / AS400 databases.

## CRITICAL WARNINGS

- These are production systems. Many are 20-30+ years old.
- **READ-ONLY by default.** No writes without explicit operator authorization.
- Always test queries with `FETCH FIRST 10 ROWS ONLY` before running full scans.
- Bad queries can lock a physical file and halt production jobs.
- Table and field names use cryptic EBCDIC conventions (6-10 chars, ALL_CAPS).
- Never DDL (CREATE/DROP/ALTER) without a mainframe DBA in the loop.

## Credentials

Credentials come from environment variables only. Never hardcoded.

```
IBMI_HOST     — system hostname or IP
IBMI_USER     — service account username
IBMI_PASSWORD — service account password (from k8s secret or .env)
IBMI_DRIVER   — ODBC driver name (default: '{IBM i Access ODBC Driver}')
IBMI_LIBRARY  — default library/schema
```

In k8s: these come from a `secretKeyRef`. In `.env`: never committed.
Read connection config from `project.toml` `[stack.databases.ibmi]` if present.

## Connection Patterns

### Node.js via ODBC (preferred for simple queries)

```typescript
import odbc from 'odbc'

const connectionString = [
  `DRIVER=${process.env.IBMI_DRIVER ?? '{IBM i Access ODBC Driver}'}`,
  `SYSTEM=${process.env.IBMI_HOST}`,
  `UID=${process.env.IBMI_USER}`,
  `PWD=${process.env.IBMI_PASSWORD}`,
  `NAM=1`,       // System naming: LIB/FILE not SCHEMA.TABLE
  `CMT=0`,       // Commit mode: 0 = immediate (no explicit transactions)
  `TRANSLATE=1`, // EBCDIC → UTF-8 auto-translation
].join(';')

// Always use a pool — connections to AS400 are expensive to create
const pool = await odbc.pool(connectionString)

export async function queryIBMi<T = unknown>(sql: string, params: unknown[] = []): Promise<T[]> {
  const conn = await pool.connect()
  try {
    return await conn.query<T>(sql, params) as T[]
  } finally {
    await conn.close()
  }
}
```

### Node.js via JT400 (better for complex operations)

```typescript
import { connect } from 'jt400'

const db = await connect({
  host: process.env.IBMI_HOST,
  user: process.env.IBMI_USER,
  password: process.env.IBMI_PASSWORD,
})
```

## SQL Dialect Gotchas

### Always TRIM fixed-width character fields

IBM i stores character fields as fixed-width (padded with spaces). Always TRIM.

```sql
-- WRONG — returns "SMITH     " not "SMITH"
SELECT PLYRFNM FROM CASINOLIB.PLAYERS

-- CORRECT
SELECT TRIM(PLYRFNM) AS first_name, TRIM(PLYRLNM) AS last_name
FROM CASINOLIB.PLAYERS
WHERE TRIM(PLYRNO) = ?
```

### Numeric date fields (NOT DATE type)

Dates are often stored as `DECIMAL(8,0)` in `YYYYMMDD` format.

```sql
-- Date stored as number: 20240315 = March 15, 2024
SELECT PLYRNO, TXNDATE, TXNAMT
FROM CASINOLIB.TXNHIST
WHERE TXNDATE >= 20240101 AND TXNDATE <= 20241231

-- Convert to real DATE if needed
SELECT DATE(
  SUBSTR(CHAR(TXNDATE), 1, 4) || '-' ||
  SUBSTR(CHAR(TXNDATE), 5, 2) || '-' ||
  SUBSTR(CHAR(TXNDATE), 7, 2)
) AS txn_date
FROM CASINOLIB.TXNHIST
```

### System naming vs SQL naming

```sql
-- System naming (NAM=1 in connection string) — use slash
SELECT * FROM CASINOLIB/PLYRMASTR FETCH FIRST 10 ROWS ONLY

-- SQL naming (NAM=0) — use dot, more portable
SELECT * FROM CASINOLIB.PLYRMASTR FETCH FIRST 10 ROWS ONLY
```

Use SQL naming (dot) in application code — it's more portable and less surprising.

### FETCH FIRST — always scope large queries

```sql
-- Before running ANY unfamiliar query on a production table:
SELECT COUNT(*) FROM CASINOLIB.TXNHIST    -- how big is this?

-- Then always use FETCH FIRST in development/testing
SELECT * FROM CASINOLIB.TXNHIST
WHERE TXNDATE = 20240315
FETCH FIRST 100 ROWS ONLY
```

### No LIMIT / OFFSET — use FETCH FIRST / OFFSET ROWS

```sql
-- IBM i DB2 pagination (not LIMIT/OFFSET)
SELECT PLYRNO, TRIM(PLYRFNM), TRIM(PLYRLNM)
FROM CASINOLIB.PLYRMASTR
ORDER BY PLYRLNM, PLYRFNM
OFFSET 20 ROWS
FETCH NEXT 10 ROWS ONLY
```

### Parameters — always use `?` placeholders

```typescript
// NEVER string interpolation in SQL
// CORRECT: parameterized
const rows = await queryIBMi(
  'SELECT TRIM(PLYRNO), TRIM(PLYRFNM), TRIM(PLYRLNM) FROM CASINOLIB.PLYRMASTR WHERE PLYRNO = ?',
  [playerId]
)
```

## File Locking

IBM i physical files can be locked by long-running queries or opened file handles.
Symptoms: jobs hang, transactions time out, other users get "file in use" errors.

Prevention:
- Close connections promptly (use `finally` blocks, connection pools)
- Never leave a cursor open across an async boundary
- Use `FETCH FIRST N ROWS ONLY` to avoid full-table locks during dev/test
- If a lock is suspected: notify the DBA — do NOT attempt to unlock yourself

## Performance

- Index usage is not guaranteed — `EXPLAIN` before running heavy queries
- `SELECT *` on large tables without a WHERE clause can hang the system
- Aggregate queries (GROUP BY, COUNT) on millions of rows without indexes = slow
- JOINs across libraries/schemas are expensive — denormalize if needed

## What We Don't Do on IBM i

- No INSERT/UPDATE/DELETE without explicit written authorization
- No schema changes (CREATE TABLE, ALTER TABLE, etc.) — DBA only
- No stored procedures without DBA review
- No running batch jobs or calling RPG programs from application code
  without documenting the interface in agent_docs/
