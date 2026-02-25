# Oracle Database Skill
# ~/.claude/forge/skills/databases/oracle.md
# Load this skill before working with Oracle databases.

## Stack Context

- Oracle accessed via `oracledb` npm package (Node.js) or `cx_Oracle`/`oracledb` (Python)
- Schema migrations managed by Flyway: `V{n}__{Description}.sql` + `U{n}__{Description}.sql`
- Credentials from env vars or k8s secrets — never hardcoded
- `sqlplus` available for CLI (requires operator confirmation in Forge)

## Credentials

```
ORACLE_HOST        — hostname
ORACLE_PORT        — port (default: 1521)
ORACLE_SERVICE     — service name (preferred over SID)
ORACLE_USER        — schema/user
ORACLE_PASSWORD    — password (k8s secret or .env, never committed)
ORACLE_WALLET_DIR  — wallet directory for production mTLS (optional)
```

Connection string formats:
```
# Easy Connect (preferred for simplicity)
host:port/service_name

# Full descriptor (when wallet required)
(DESCRIPTION=(ADDRESS=(PROTOCOL=TCPS)(HOST=host)(PORT=2484))(CONNECT_DATA=(SERVICE_NAME=svc)))
```

Read connection config from `project.toml` `[stack.databases.oracle]` if present.

## Connection Patterns

### Node.js (oracledb package)

```typescript
import oracledb from 'oracledb'

// Thin mode — no Oracle Client required (oracledb 6.0+)
oracledb.initOracleClient()  // remove this line for thin mode

const pool = await oracledb.createPool({
  user:             process.env.ORACLE_USER!,
  password:         process.env.ORACLE_PASSWORD!,
  connectString:    `${process.env.ORACLE_HOST}:${process.env.ORACLE_PORT ?? '1521'}/${process.env.ORACLE_SERVICE}`,
  poolMin:          2,
  poolMax:          10,
  poolIncrement:    2,
  poolTimeout:      60,
  stmtCacheSize:    30,
})

// Enable object output (not arrays)
oracledb.outFormat = oracledb.OUT_FORMAT_OBJECT

export async function query<T = Record<string, unknown>>(
  sql: string,
  params: Record<string, unknown> = {}
): Promise<T[]> {
  const conn = await pool.getConnection()
  try {
    const result = await conn.execute<T>(sql, params, { outFormat: oracledb.OUT_FORMAT_OBJECT })
    return result.rows ?? []
  } finally {
    await conn.close()
  }
}
```

### Python (oracledb package — thin mode)

```python
import oracledb
import os

# Thin mode: no Oracle Client installation required
pool = oracledb.create_pool(
    user=os.environ['ORACLE_USER'],
    password=os.environ['ORACLE_PASSWORD'],
    dsn=f"{os.environ['ORACLE_HOST']}:{os.environ.get('ORACLE_PORT', '1521')}/{os.environ['ORACLE_SERVICE']}",
    min=2, max=10, increment=2
)

def query(sql: str, params: dict | None = None) -> list[dict]:
    with pool.acquire() as conn:
        with conn.cursor() as cur:
            cur.execute(sql, params or {})
            cols = [col[0].lower() for col in cur.description]
            return [dict(zip(cols, row)) for row in cur.fetchall()]
```

## Oracle SQL Dialect — Key Differences

### Parameters — use named binds (`:name`), not `?`

```typescript
// Oracle uses :param_name style, not ?
const rows = await query(
  'SELECT player_id, first_name FROM players WHERE player_id = :id AND active = :active',
  { id: playerId, active: 1 }
)
```

### Pagination — OFFSET/FETCH (Oracle 12c+) or ROWNUM

```sql
-- Oracle 12c+ (preferred)
SELECT player_id, first_name, last_name
FROM players
ORDER BY last_name, first_name
OFFSET 20 ROWS FETCH NEXT 10 ROWS ONLY

-- Oracle 11g and earlier (use ROWNUM subquery)
SELECT * FROM (
  SELECT a.*, ROWNUM AS rn FROM (
    SELECT player_id, first_name, last_name
    FROM players
    ORDER BY last_name, first_name
  ) a WHERE ROWNUM <= 30
) WHERE rn > 20
```

### Date/time functions (not NOW(), not GETDATE())

```sql
SYSDATE           -- current date+time (database server local time)
SYSTIMESTAMP      -- current timestamp with fractional seconds
CURRENT_TIMESTAMP -- current timestamp in session timezone
TRUNC(SYSDATE)    -- today at midnight
TRUNC(SYSDATE, 'MM')  -- first day of current month

-- Date arithmetic: + N adds N days
SYSDATE - 7       -- 7 days ago
SYSDATE + 1/24    -- 1 hour from now

-- Format as string
TO_CHAR(created_at, 'YYYY-MM-DD HH24:MI:SS')

-- String to date
TO_DATE('2024-03-15', 'YYYY-MM-DD')
TO_TIMESTAMP('2024-03-15 14:30:00', 'YYYY-MM-DD HH24:MI:SS')
```

### String functions

```sql
LENGTH(str)           -- character length
SUBSTR(str, 1, 10)    -- substring (1-indexed)
INSTR(str, 'x')       -- find char (1-indexed, 0 = not found)
TRIM(str)             -- trim both sides
LTRIM(str) / RTRIM(str)
NVL(col, default)     -- replace NULL (Oracle-specific)
NVL2(col, if_not_null, if_null)
COALESCE(a, b, c)     -- standard NULL coalescing
```

### Sequences (Oracle's auto-increment)

Oracle doesn't have auto-increment columns the same way as other DBs.
Use sequences + triggers (older pattern) or IDENTITY columns (12c+).

```sql
-- 12c+ IDENTITY (preferred for new tables)
CREATE TABLE players (
  player_id  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  first_name VARCHAR2(100) NOT NULL,
  created_at TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL
)

-- Older pattern: explicit sequence
CREATE SEQUENCE players_seq START WITH 1 INCREMENT BY 1 NOCACHE NOCYCLE;

INSERT INTO players (player_id, first_name)
VALUES (players_seq.NEXTVAL, :first_name)
RETURNING player_id INTO :new_id
```

### DUAL table — for expressions without a real table

```sql
-- Oracle requires FROM clause even for expressions
SELECT SYSDATE FROM DUAL
SELECT 1 + 1 AS result FROM DUAL
SELECT players_seq.NEXTVAL FROM DUAL
```

### String concatenation — use `||`

```sql
SELECT first_name || ' ' || last_name AS full_name FROM players
-- NOT +, NOT CONCAT() (though CONCAT() exists but only takes 2 args)
```

## Flyway Migrations

Same conventions as MSSQL — see mssql.md for full rules.

Oracle-specific migration notes:
- Oracle DDL statements are NOT transactional (DDL auto-commits)
- `COMMIT` after DML but DDL is already committed
- Schema changes cannot be rolled back — forward-only is safer
- Use `EXECUTE IMMEDIATE` in PL/SQL for dynamic DDL in procedures

```sql
-- V5__Add_session_table.sql
CREATE TABLE player_sessions (
  session_id  NUMBER GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  player_id   NUMBER NOT NULL,
  started_at  TIMESTAMP DEFAULT SYSTIMESTAMP NOT NULL,
  ended_at    TIMESTAMP,
  active      NUMBER(1) DEFAULT 1 NOT NULL,
  CONSTRAINT fk_sessions_player FOREIGN KEY (player_id) REFERENCES players(player_id),
  CONSTRAINT chk_active CHECK (active IN (0, 1))
);

CREATE INDEX idx_sessions_player ON player_sessions(player_id);
CREATE INDEX idx_sessions_active ON player_sessions(active, started_at);
```

## Transactions

```typescript
// Oracle connections auto-start a transaction
// Must explicitly COMMIT or ROLLBACK
const conn = await pool.getConnection()
try {
  await conn.execute('UPDATE players SET active = 0 WHERE player_id = :id', { id })
  await conn.execute('INSERT INTO audit_log (action, player_id, ts) VALUES (:action, :id, SYSTIMESTAMP)', {
    action: 'DEACTIVATE', id
  })
  await conn.commit()
} catch (err) {
  await conn.rollback()
  throw err
} finally {
  await conn.close()
}
```

## Performance Patterns

- Oracle optimizes based on statistics — run `DBMS_STATS.GATHER_TABLE_STATS` after bulk inserts
- Bind variables (`:name`) are critical for execution plan reuse — never concatenate SQL
- `EXPLAIN PLAN FOR` to check query plans before deploying to production
- Avoid `SELECT *` in production — name columns explicitly
- For large exports: use cursor/streaming, not fetching all rows into memory

## What to Always Avoid

- String concatenation in SQL queries (SQL injection + plan cache pollution)
- Hardcoded credentials anywhere
- `DROP TABLE` / `TRUNCATE TABLE` in Flyway forward migrations
- Editing already-run migration files
- `SELECT *` in production application code
- Assuming Oracle behaves like PostgreSQL — key differences: no boolean type,
  empty string = NULL, ROWNUM quirks, DATE includes time component
