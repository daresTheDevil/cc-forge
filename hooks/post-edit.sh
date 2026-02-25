#!/usr/bin/env bash
# .claude/hooks/post-edit.sh
# CC-Forge Post-Edit Hook
# Runs after every file edit. Auto-fixes formatting (deterministic).
# Surfaces issues to Claude rather than letting them accumulate.

set -uo pipefail

EDITED_FILE="${CLAUDE_TOOL_INPUT_FILE_PATH:-}"

if [ -z "$EDITED_FILE" ]; then
  exit 0
fi

# ---------------------------------------------------------------------------
# Auto-format TypeScript/JavaScript files after every edit
# Don't make Claude hunt for formatting issues — fix them automatically
# ---------------------------------------------------------------------------
if [[ "$EDITED_FILE" =~ \.(ts|tsx|js|jsx|mjs)$ ]]; then
  if command -v bunx &> /dev/null && [ -f "biome.json" -o -f "biome.jsonc" ]; then
    bunx biome format --write "$EDITED_FILE" 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# Auto-format Python files after every edit
# ---------------------------------------------------------------------------
if [[ "$EDITED_FILE" =~ \.py$ ]]; then
  if command -v black &> /dev/null; then
    black "$EDITED_FILE" 2>/dev/null || true
  fi
  if command -v isort &> /dev/null; then
    isort "$EDITED_FILE" 2>/dev/null || true
  fi
fi

# ---------------------------------------------------------------------------
# Surface TypeScript errors immediately after editing a TS file
# Don't wait until commit — fail fast
# ---------------------------------------------------------------------------
if [[ "$EDITED_FILE" =~ \.(ts|tsx)$ ]]; then
  ERRORS=$(bun run typecheck 2>&1 | grep -c "error TS" || true)
  if [ "$ERRORS" -gt 0 ]; then
    echo "⚠️  CC-Forge: $ERRORS TypeScript error(s) after editing $EDITED_FILE"
    echo "   Run: bun run typecheck"
  fi
fi

exit 0
