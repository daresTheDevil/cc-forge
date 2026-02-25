#!/usr/bin/env bash
# .claude/hooks/pre-commit.sh
# CC-Forge Pre-Commit Hook
# Runs deterministic gates BEFORE Claude commits anything.
# These are not LLM tasks — they are fast, deterministic checks.
# If any gate fails, the commit is blocked and the error is surfaced to Claude.

set -euo pipefail

echo "🔒 CC-Forge pre-commit gates running..."

ERRORS=0

# ---------------------------------------------------------------------------
# Gate 1: Secret scanning
# Never let credentials reach git history
# ---------------------------------------------------------------------------
echo "  [1/5] Secret scan..."
if command -v git-secrets &> /dev/null; then
  if ! git secrets --scan; then
    echo "  ❌ BLOCKED: Potential secrets detected. Remove them before committing."
    ERRORS=$((ERRORS + 1))
  fi
elif command -v trufflehog &> /dev/null; then
  if ! trufflehog git file://. --since-commit HEAD --only-verified --fail; then
    echo "  ❌ BLOCKED: Verified secrets detected."
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "  ⚠️  WARNING: No secret scanner found. Install git-secrets or trufflehog."
fi

# ---------------------------------------------------------------------------
# Gate 2: TypeScript typecheck (JS/TS projects)
# Type errors are defects — never commit them
# ---------------------------------------------------------------------------
if [ -f "package.json" ]; then
  echo "  [2/5] TypeScript check..."
  if ! bun run typecheck 2>&1; then
    echo "  ❌ BLOCKED: TypeScript errors found. Fix before committing."
    ERRORS=$((ERRORS + 1))
  fi
fi

# ---------------------------------------------------------------------------
# Gate 3: Linting (Biome or ESLint)
# Formatting and lint issues are deterministic — fix them automatically where safe
# ---------------------------------------------------------------------------
if [ -f "biome.json" ] || [ -f "biome.jsonc" ]; then
  echo "  [3/5] Biome lint + format check..."
  if ! bunx biome check --error-on-warnings .; then
    echo "  ❌ BLOCKED: Lint/format issues found. Run: bunx biome check --apply ."
    ERRORS=$((ERRORS + 1))
  fi
elif [ -f ".eslintrc*" ] || [ -f "eslint.config*" ]; then
  echo "  [3/5] ESLint check..."
  if ! bun run lint; then
    echo "  ❌ BLOCKED: Lint issues found."
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "  [3/5] No linter configured — skipping."
fi

# ---------------------------------------------------------------------------
# Gate 4: Database migration safety check
# Detect destructive SQL patterns — block before they reach version control
# ---------------------------------------------------------------------------
STAGED_MIGRATIONS=$(git diff --cached --name-only | grep -E "db/migrations/V.*\.sql" || true)
if [ -n "$STAGED_MIGRATIONS" ]; then
  echo "  [4/5] Migration safety check..."
  DESTRUCTIVE_PATTERNS="DROP TABLE|DROP COLUMN|TRUNCATE|DELETE FROM [^W]|ALTER COLUMN.*DROP"
  for migration in $STAGED_MIGRATIONS; do
    if grep -qiE "$DESTRUCTIVE_PATTERNS" "$migration"; then
      echo "  ❌ BLOCKED: Destructive SQL pattern detected in $migration"
      echo "     Destructive migrations require break-glass override in project.toml"
      echo "     Patterns flagged: DROP TABLE, DROP COLUMN, TRUNCATE, DELETE without WHERE"
      ERRORS=$((ERRORS + 1))
    fi
    # Check rollback script exists
    # Correct path: db/migrations/V3__Foo.sql → db/migrations/undo/U3__Foo.sql
    UNDO_SCRIPT="db/migrations/undo/U${migration#db/migrations/V}"
    if [ ! -f "$UNDO_SCRIPT" ]; then
      echo "  ❌ BLOCKED: No rollback script for $migration"
      echo "     Expected: ${UNDO_SCRIPT}"
      ERRORS=$((ERRORS + 1))
    fi
  done
  if [ $ERRORS -eq 0 ]; then
    echo "  ✅ Migration safety check passed."
  fi
else
  echo "  [4/5] No migrations staged — skipping."
fi

# ---------------------------------------------------------------------------
# Gate 5: Conventional commit message format
# Enforced for traceability and automated changelog generation
# ---------------------------------------------------------------------------
echo "  [5/5] Commit message format..."
COMMIT_MSG_FILE="${1:-}"
if [ -n "$COMMIT_MSG_FILE" ] && [ -f "$COMMIT_MSG_FILE" ]; then
  COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")
  PATTERN="^(feat|fix|chore|refactor|test|docs|perf|ci|build|sec|improve|simplify)(\([a-z0-9-]+\))?: .{10,}"
  if ! echo "$COMMIT_MSG" | grep -qE "$PATTERN"; then
    echo "  ❌ BLOCKED: Commit message doesn't follow conventional commits format."
    echo "     Expected: type(scope): description (min 10 chars)"
    echo "     Types: feat|fix|chore|refactor|test|docs|perf|ci|build|sec|improve|simplify"
    echo "     Got: $COMMIT_MSG"
    ERRORS=$((ERRORS + 1))
  fi
else
  echo "  [5/5] No commit message file provided — skipping format check."
fi

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
if [ $ERRORS -gt 0 ]; then
  echo ""
  echo "❌ CC-Forge pre-commit: $ERRORS gate(s) failed. Commit blocked."
  echo "   Fix the issues above and try again."
  exit 1
else
  echo ""
  echo "✅ CC-Forge pre-commit: all gates passed."
  exit 0
fi
