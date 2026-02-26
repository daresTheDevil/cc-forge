#!/usr/bin/env bash

CYAN='\033[36m'
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
DIM='\033[2m'
BOLD='\033[1m'
NC='\033[0m'

SEP="${DIM}│${NC}"

# Context threshold — at this usage %, trigger background handoff and show warning.
# Defined here (not inline in logic) so it can be changed without hunting through code.
CONTEXT_THRESHOLD=70

# Parse stdin — Claude Code passes a JSON payload including context_window.used_percentage.
# Non-blocking: cat with 2>/dev/null so missing/empty stdin never hangs the render path.
STATUSLINE_INPUT=$(cat 2>/dev/null)
CONTEXT_PCT=""
if [ -n "$STATUSLINE_INPUT" ] && command -v jq >/dev/null 2>&1; then
  CONTEXT_PCT=$(echo "$STATUSLINE_INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
fi

# Context threshold detection — fires at most once per session (flag file guard).
# All paths wrapped in 2>/dev/null so a broken .forge/ state never corrupts the bar.
CONTEXT_WARNING=""
if [[ "$CONTEXT_PCT" =~ ^[0-9]+$ ]] && [ "$CONTEXT_PCT" -ge "$CONTEXT_THRESHOLD" ] 2>/dev/null; then
  CONTEXT_WARNING=" ${YELLOW}⚠ CTX ${CONTEXT_PCT}%%${NC}"
  if [ ! -f ".forge/logs/context-threshold-triggered" ]; then
    mkdir -p .forge/logs 2>/dev/null
    touch .forge/logs/context-threshold-triggered 2>/dev/null
    (nohup ~/.claude/forge/context-handoff.sh >/dev/null 2>&1 &)
  fi
fi

# cc-forge version
FORGE_VERSION="?"
FORGE_PKG="$(npm prefix -g 2>/dev/null)/lib/node_modules/cc-forge/package.json"
if [[ -f "$FORGE_PKG" ]] && command -v jq &>/dev/null; then
  FORGE_VERSION="$(jq -r '.version' "$FORGE_PKG" 2>/dev/null || echo "?")"
fi

# Project name
PROJECT="$(basename "$PWD")"

# Git branch and dirty count
GIT_BRANCH="$(git branch --show-current 2>/dev/null)"
if [[ -z "$GIT_BRANCH" ]]; then
  GIT_INFO="${DIM}no git${NC}"
else
  DIRTY_COUNT="$(git status --short 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "$DIRTY_COUNT" -eq 0 ]]; then
    DIRTY_STATUS="${DIM}clean${NC}"
  else
    DIRTY_STATUS="${YELLOW}[${DIRTY_COUNT}]${NC}"
  fi
  GIT_INFO="${GREEN}${GIT_BRANCH}${NC} ${DIRTY_STATUS}"
fi

# Forge phase/tasks
GOLEM_STATE=""
STATE_FILE="${PWD}/.claude/forge/forge-state.json"
if [[ -f "$STATE_FILE" ]] && command -v jq &>/dev/null; then
  PHASE="$(jq -r '.phase // empty' "$STATE_FILE" 2>/dev/null)"
  TASKS_COMPLETED="$(jq -r '.tasks_completed // empty' "$STATE_FILE" 2>/dev/null)"
  TASKS_TOTAL="$(jq -r '.tasks_total // empty' "$STATE_FILE" 2>/dev/null)"
  if [[ -n "$PHASE" && -n "$TASKS_COMPLETED" && -n "$TASKS_TOTAL" ]]; then
    PHASE_COLOR="${YELLOW}"
    case "$PHASE" in
      "complete"|"completed") PHASE_COLOR="${GREEN}" ;;
      "blocked"|"error") PHASE_COLOR="${RED}" ;;
    esac
    GOLEM_STATE="${SEP} ${PHASE_COLOR}${PHASE}${NC} ${DIM}${TASKS_COMPLETED}/${TASKS_TOTAL}${NC}"
  fi
fi

# Usage stats from cache
USAGE_INFO=""
RATE_LIMIT_INFO=""
CACHE_FILE="${HOME}/.claude/usage-cache.json"
if [[ -f "$CACHE_FILE" ]] && command -v jq &>/dev/null; then
  # Check if cache is fresh (< 5 minutes old)
  CACHE_AGE=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
  if [[ $CACHE_AGE -lt 300 ]]; then
    TODAY_TOTAL="$(jq -r '.today.total // empty' "$CACHE_FILE" 2>/dev/null)"
    WEEK_TOTAL="$(jq -r '.week.total // empty' "$CACHE_FILE" 2>/dev/null)"

    if [[ -n "$TODAY_TOTAL" || -n "$WEEK_TOTAL" ]]; then
      USAGE_INFO="${DIM}today${NC} ${TODAY_TOTAL} ${SEP} ${DIM}week${NC} ${WEEK_TOTAL} "
    fi

    # Rate limits
    FIVE_H_PCT="$(jq -r '.rateLimits.fiveHour.pct // empty' "$CACHE_FILE" 2>/dev/null)"
    FIVE_H_RESET="$(jq -r '.rateLimits.fiveHour.reset // empty' "$CACHE_FILE" 2>/dev/null)"
    OPUS_PCT="$(jq -r '.rateLimits.opus7d.pct // empty' "$CACHE_FILE" 2>/dev/null)"
    OPUS_RESET="$(jq -r '.rateLimits.opus7d.reset // empty' "$CACHE_FILE" 2>/dev/null)"
    SONNET_PCT="$(jq -r '.rateLimits.sonnet7d.pct // empty' "$CACHE_FILE" 2>/dev/null)"
    SONNET_RESET="$(jq -r '.rateLimits.sonnet7d.reset // empty' "$CACHE_FILE" 2>/dev/null)"

    if [[ -n "$FIVE_H_PCT" ]]; then
      # Color function
      get_color() {
        local pct=$1
        if [[ $pct -ge 80 ]]; then echo "$RED"
        elif [[ $pct -ge 50 ]]; then echo "$YELLOW"
        else echo "$GREEN"
        fi
      }

      # 5h limit
      FIVE_COLOR=$(get_color $FIVE_H_PCT)
      FIVE_RESET=""
      [[ -n "$FIVE_H_RESET" ]] && FIVE_RESET=" ${DIM}${FIVE_H_RESET}${NC}"

      # Opus 7d
      OPUS_COLOR=$(get_color ${OPUS_PCT:-0})
      OPUS_DISPLAY=""
      if [[ -n "$OPUS_PCT" ]]; then
        OPUS_R=""
        [[ -n "$OPUS_RESET" ]] && OPUS_R=" ${DIM}${OPUS_RESET}${NC}"
        OPUS_DISPLAY=" ${SEP} ${DIM}opus${NC} ${OPUS_COLOR}${OPUS_PCT}%%${NC}${OPUS_R}"
      fi

      # Sonnet 7d
      SONNET_COLOR=$(get_color ${SONNET_PCT:-0})
      SONNET_DISPLAY=""
      if [[ -n "$SONNET_PCT" ]]; then
        SONNET_R=""
        [[ -n "$SONNET_RESET" ]] && SONNET_R=" ${DIM}${SONNET_RESET}${NC}"
        SONNET_DISPLAY=" ${SEP} ${DIM}sonnet${NC} ${SONNET_COLOR}${SONNET_PCT}%%${NC}${SONNET_R}"
      fi

      RATE_LIMIT_INFO="${SEP} ${DIM}5h${NC} ${FIVE_COLOR}${FIVE_H_PCT}%%${NC}${FIVE_RESET}${OPUS_DISPLAY}${SONNET_DISPLAY}"
    fi
  else
    # Cache is stale, trigger update in background (don't wait)
    (nohup ~/.claude/update-usage-cache.mjs >/dev/null 2>&1 &)
  fi
fi

# Time
TIME="$(date +"%H:%M")"

# Line 1: forge version | time | pwd | git status | context warning (if threshold crossed)
printf " ${BOLD}${CYAN}Forge v${FORGE_VERSION}${NC} ${SEP} ${DIM}${TIME}${NC} ${SEP} ${CYAN}${PROJECT}${NC} ${SEP} ${GIT_INFO}${GOLEM_STATE}${CONTEXT_WARNING}\n"

# Line 2: all the rate limit stuff
printf " ${USAGE_INFO}${RATE_LIMIT_INFO}\n"

# Line 3: blank spacer (Braille blank U+2800 — invisible but non-whitespace)
echo "⠀"

# Line 4: dim separator
printf " ${DIM}─────────────────────────────────────────────────${NC}\n"
