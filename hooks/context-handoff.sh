#!/usr/bin/env bash
# hooks/context-handoff.sh
# CC-Forge Context Threshold Handoff
#
# Invoked by statusline.sh when context usage crosses CONTEXT_THRESHOLD.
# Runs detached (nohup background) from the statusline render path.
# MUST be completely silent (all output suppressed) and MUST exit 0 always.
#
# Installed to: ~/.claude/forge/context-handoff.sh (global install)
#
# What it does:
#   1. Creates .forge/handoffs/ in the current project if needed
#   2. Writes a minimal handoff file with timestamp, branch, uncommitted count,
#      forge phase/task, and a note that this was auto-triggered by context threshold
#   3. Writes the absolute handoff path to ~/.claude/pending-resume
#      so the next session auto-loads the handoff via /forge--continue

# Redirect all stdout and stderr to /dev/null — this runs on the render path
exec >/dev/null 2>&1

# Determine project dir (where the script was launched from, not the script location)
PROJECT_DIR="${PWD}"

# Ensure the handoffs directory exists
mkdir -p "${PROJECT_DIR}/.forge/handoffs"

# Collect state — all with graceful fallbacks
TIMESTAMP=$(date +%Y%m%d-%H%M%S 2>/dev/null || echo "00000000-000000")
TIMESTAMP_ISO=$(date -u +%Y-%m-%dT%H:%M:%S 2>/dev/null || echo "unknown")
BRANCH=$(git -C "$PROJECT_DIR" branch --show-current 2>/dev/null || echo "unknown")
UNCOMMITTED=$(git -C "$PROJECT_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' ' || echo "0")

FORGE_PHASE="unknown"
FORGE_TASK="none"
STATE_FILE="${PROJECT_DIR}/.forge/state.json"
if [ -f "$STATE_FILE" ] && command -v jq >/dev/null 2>&1; then
  FORGE_PHASE=$(jq -r '.phase // "unknown"' "$STATE_FILE" 2>/dev/null || echo "unknown")
  FORGE_TASK=$(jq -r '.build.current_task // "none"' "$STATE_FILE" 2>/dev/null || echo "none")
fi

# Write the handoff file
HANDOFF_PATH="${PROJECT_DIR}/.forge/handoffs/handoff-${TIMESTAMP}.md"

cat > "$HANDOFF_PATH" <<HANDOFF_EOF
# CC-Forge Auto Handoff — Context Threshold Triggered
Timestamp: ${TIMESTAMP_ISO}
Branch: ${BRANCH}
Uncommitted changes: ${UNCOMMITTED}
Forge phase: ${FORGE_PHASE}
Forge task: ${FORGE_TASK}
Trigger: Automatic — context window usage crossed threshold

## Note
This handoff was written automatically by context-handoff.sh when the
context window usage crossed the configured CONTEXT_THRESHOLD in statusline.sh.

The session state captured here is minimal. For full context, review:
- \`.forge/logs/last-session.json\` (if present)
- Recent git log: \`git log --oneline -10\`

## Resume
To resume from this handoff, run \`/forge--continue\` in the next session.
HANDOFF_EOF

# Write absolute path to pending-resume so next session auto-loads this handoff
CLAUDE_DIR="${HOME}/.claude"
mkdir -p "$CLAUDE_DIR"
printf '%s\n' "$HANDOFF_PATH" > "${CLAUDE_DIR}/pending-resume"

exit 0
