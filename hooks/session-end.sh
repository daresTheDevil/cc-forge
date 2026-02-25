#!/usr/bin/env bash
# .claude/hooks/session-end.sh
# CC-Forge Session End Hook
# Runs when Claude Code stops. Reminds Claude to update progress tracking.
# This is a reminder surface, not enforcement — Claude writes the actual update.

set -uo pipefail

PROGRESS_FILE="claude-progress.txt"
TODAY=$(date +%Y-%m-%d)

# Append a session-end prompt to the progress file if it exists
# Claude is expected to fill in the content during its session-end step
if [ -f "$PROGRESS_FILE" ]; then
  echo "" >> "$PROGRESS_FILE"
  echo "## [$TODAY] — Session ended (fill in before closing)" >> "$PROGRESS_FILE"
  echo "Status: " >> "$PROGRESS_FILE"
  echo "Completed: " >> "$PROGRESS_FILE"
  echo "Next: " >> "$PROGRESS_FILE"
  echo "Blockers: " >> "$PROGRESS_FILE"
fi

# Check for uncommitted changes — surface as a warning
UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
if [ "$UNCOMMITTED" -gt 0 ]; then
  echo "⚠️  CC-Forge: Session ending with $UNCOMMITTED uncommitted change(s)."
  echo "   Commit your progress before ending the session or stash for next time."
fi

exit 0
