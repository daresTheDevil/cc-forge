#!/usr/bin/env bash
# .claude/hooks/commit-msg.sh
# CC-Forge Commit-Msg Hook
# Enforces conventional commit format on every commit message.
# Install as .git/hooks/commit-msg (not a Claude Code hook — a git hook)
#
# Usage: Configure in project with:
#   cp .claude/hooks/commit-msg.sh .git/hooks/commit-msg
#   chmod +x .git/hooks/commit-msg
#
# Note: The pre-commit.sh check is a no-op because pre-commit hooks do not
# receive the commit message file as $1. This hook is the correct place for
# conventional commit enforcement.

COMMIT_MSG_FILE="${1:?commit-msg hook requires the commit message file path as \$1}"

if [ ! -f "$COMMIT_MSG_FILE" ]; then
  echo "ERROR: Commit message file not found: $COMMIT_MSG_FILE" >&2
  exit 1
fi

COMMIT_MSG=$(cat "$COMMIT_MSG_FILE")

# Strip comments (lines starting with #) and blank lines before checking
COMMIT_MSG_CLEAN=$(printf '%s\n' "$COMMIT_MSG" | grep -v '^#' | sed '/^$/d' | head -1)

if [ -z "$COMMIT_MSG_CLEAN" ]; then
  echo "BLOCKED [CC-Forge]: Commit message is empty." >&2
  exit 1
fi

# Conventional commits pattern
# Types: feat|fix|chore|refactor|test|docs|perf|ci|build|sec|improve|simplify
PATTERN="^(feat|fix|chore|refactor|test|docs|perf|ci|build|sec|improve|simplify)(\([a-z0-9_-]+\))?: .{10,}"

if ! printf '%s' "$COMMIT_MSG_CLEAN" | grep -qE "$PATTERN"; then
  echo "" >&2
  echo "BLOCKED [CC-Forge]: Commit message does not follow conventional commits format." >&2
  echo "" >&2
  echo "  Expected: type(scope): description (min 10 chars)" >&2
  echo "  Types:    feat|fix|chore|refactor|test|docs|perf|ci|build|sec|improve|simplify" >&2
  echo "  Examples: feat(auth): add JWT refresh token support" >&2
  echo "            fix(api): handle null response from payment gateway" >&2
  echo "            test(db): add migration rollback characterization tests" >&2
  echo "" >&2
  echo "  Got: $COMMIT_MSG_CLEAN" >&2
  echo "" >&2
  exit 1
fi

exit 0
