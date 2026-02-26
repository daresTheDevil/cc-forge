#!/usr/bin/env bash
# .claude/hooks/session-end.sh
# CC-Forge Session End Hook (Stop event)
# Writes machine-readable state to .forge/logs/last-session.json
# Writes learn-pending flag to .forge/logs/learn-pending
# Warns on dirty tree
# Degrades gracefully if jq or git are unavailable
# Always exits 0

# Read hook context from stdin (non-blocking — default to empty string)
INPUT=$(cat 2>/dev/null || true)

# ── Ensure output directory exists ─────────────────────────────────────────
mkdir -p .forge/logs 2>/dev/null || true

# ── Collect state ──────────────────────────────────────────────────────────
ENDED_AT=$(date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo "unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ' || echo "0")

# Read forge phase and task from .forge/state.json if available
FORGE_PHASE="unknown"
FORGE_TASK="none"
if [ -f ".forge/state.json" ] && command -v jq >/dev/null 2>&1; then
  FORGE_PHASE=$(jq -r '.phase // "unknown"' .forge/state.json 2>/dev/null || echo "unknown")
  FORGE_TASK=$(jq -r '.task // "none"' .forge/state.json 2>/dev/null || echo "none")
fi

# ── Write last-session.json (requires jq for robust JSON serialization) ────
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg ended_at "$ENDED_AT" \
    --arg branch "$BRANCH" \
    --argjson uncommitted_changes "$UNCOMMITTED" \
    --arg forge_phase "$FORGE_PHASE" \
    --arg forge_task "$FORGE_TASK" \
    '{
      ended_at: $ended_at,
      branch: $branch,
      uncommitted_changes: $uncommitted_changes,
      forge_phase: $forge_phase,
      forge_task: $forge_task
    }' > .forge/logs/last-session.json 2>/dev/null || true
else
  # Graceful degradation: write minimal JSON without jq
  printf '{"ended_at":"%s","branch":"%s","uncommitted_changes":%s,"forge_phase":"%s","forge_task":"%s"}\n' \
    "$ENDED_AT" "$BRANCH" "$UNCOMMITTED" "$FORGE_PHASE" "$FORGE_TASK" \
    > .forge/logs/last-session.json 2>/dev/null || true
fi

# ── Write learn-pending flag ────────────────────────────────────────────────
touch .forge/logs/learn-pending 2>/dev/null || true

# ── Warn on dirty tree ─────────────────────────────────────────────────────
if [ -n "$UNCOMMITTED" ] && [ "$UNCOMMITTED" -gt 0 ] 2>/dev/null; then
  echo "[CC-Forge] Session ending with ${UNCOMMITTED} uncommitted change(s). Commit or stash before next session."
fi

exit 0
