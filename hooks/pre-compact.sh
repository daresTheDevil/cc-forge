#!/usr/bin/env bash
# hooks/pre-compact.sh
# CC-Forge PreCompact Hook
# Fires at PreCompact event — captures working state before Claude Code auto-compaction.
# SILENT: produces zero stdout output. All output suppressed — runs on the render path.

# Read stdin non-blocking (hook context may be piped in)
INPUT=$(cat 2>/dev/null)

# Ensure output directory exists (silent)
mkdir -p .forge/logs 2>/dev/null

# Collect state values
CAPTURED_AT=$(date -u +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || echo "unknown")
BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
UNCOMMITTED=$(git status --porcelain 2>/dev/null | { wc -l 2>/dev/null || echo 0; } | { tr -d ' ' 2>/dev/null || cat; })
# Default to 0 if wc/tr unavailable or output is non-numeric
[[ "$UNCOMMITTED" =~ ^[0-9]+$ ]] || UNCOMMITTED=0
RECENT_FILES_RAW=$(git diff --name-only HEAD 2>/dev/null | { head -10 2>/dev/null || cat; })

# Build recent_files JSON array without jq (pure bash)
# Each file becomes a quoted string element
FILES_JSON="["
FIRST=1
while IFS= read -r line; do
  if [ -n "$line" ]; then
    # Escape any double quotes in the filename (safe for typical paths)
    ESCAPED=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g' 2>/dev/null)
    if [ "$FIRST" -eq 1 ]; then
      FILES_JSON="${FILES_JSON}\"${ESCAPED}\""
      FIRST=0
    else
      FILES_JSON="${FILES_JSON},\"${ESCAPED}\""
    fi
  fi
done <<< "$RECENT_FILES_RAW"
FILES_JSON="${FILES_JSON}]"

# Write state JSON — requires jq for pretty output; falls back to manual construction
if command -v jq >/dev/null 2>&1; then
  jq -n \
    --arg captured_at "$CAPTURED_AT" \
    --arg branch "$BRANCH" \
    --argjson uncommitted_changes "$UNCOMMITTED" \
    --argjson recent_files "$FILES_JSON" \
    '{
      captured_at: $captured_at,
      branch: $branch,
      uncommitted_changes: $uncommitted_changes,
      recent_files: $recent_files
    }' > .forge/logs/pre-compact-state.json 2>/dev/null
else
  # Manual JSON construction when jq is unavailable
  printf '{\n  "captured_at": "%s",\n  "branch": "%s",\n  "uncommitted_changes": %s,\n  "recent_files": %s\n}\n' \
    "$CAPTURED_AT" "$BRANCH" "$UNCOMMITTED" "$FILES_JSON" \
    > .forge/logs/pre-compact-state.json 2>/dev/null
fi

exit 0
