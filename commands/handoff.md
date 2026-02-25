---
description: Create a structured session handoff. Captures full Forge project state so the next session resumes seamlessly via /forge--continue or auto-injection on session start.
allowed-tools: Read, Write, Bash, Glob, Grep
---

# CC-Forge Handoff — Session Capture

You are creating a session handoff document. Goal: capture enough state that a
fresh Claude session can resume without re-asking questions, re-reading files,
or rediscovering decisions already made this session.

Two layers:
1. **Factual** — gathered from files and commands (read them; don't guess)
2. **Conversational** — written from your knowledge of this session

---

## Phase 1: Gather Project Facts

### 1. Forge State

Read `.forge/state.json`:
- Current phase
- Current task (if any)
- Completed tasks count

Read `.claude/forge/project.toml`:
- `project.id`, `project.name`, `workspace`

### 2. Security Posture

Read `.forge/security.json`:
- `scores.overall`
- `findings.code.critical` and `findings.code.high`
- `last_audit`

If critical > 0, flag it prominently in the handoff.

### 3. Git State

```bash
git branch --show-current
git status --short
git log --oneline -10
```

Record: branch name, clean/dirty (list changed files if dirty), last 10 commits.

### 4. Recent Session Activity

Read `.forge/logs/file-changes.log` — last 20 entries.
These show exactly what was touched this session.

### 5. Progress Log

Read `claude-progress.txt` — last 20 lines.

### 6. Active Plan (if one exists)

Glob for `plan-*.md` in the project root. If found:
- Count `- [x]` (complete) vs `- [ ]` (pending)
- List in-progress items (those between the last `[x]` and the remaining `[ ]`)
- Note the plan filename for the next session to reference

### 7. Agent Docs Staleness Check

Read the `last_verified` field from each `.claude/agent_docs/*.md` header.
Flag any doc where `last_verified` is older than 14 days as potentially stale.

---

## Phase 2: Conversational Context

From your knowledge of this session, write these sections honestly.
A future Claude will trust this — make it accurate.

### Current Focus
What was actively being worked on? Name specific files, features, tasks, or bugs.
Not "working on the API" — "adding rate limiting to POST /api/players endpoint in
services/player-api/src/routes/players.ts."

### What's Next
Ordered, actionable next steps. Specific enough that Claude can start immediately.
- "Run `bun run typecheck` — there are 3 errors in src/types/player.ts"
- "Implement T004: write the Zod schema for PlayerSession before touching the route"
- "Review the failing test in player.test.ts — it's asserting the wrong status code"

### Decisions Made
Key decisions from this conversation that aren't captured in code or docs.
Include the WHY — rationale that would be lost if not written down.

### Gotchas / Don't Forget
Things that would be easy to forget and would waste time rediscovering.
"The k8s secret name is `player-api-db-creds`, not `player-db-credentials`."
"IBM i FETCH FIRST 10 ROWS ONLY before any full table scan."

---

## Phase 3: Assemble and Write

Combine all sections. Write to:
```
.forge/handoffs/handoff-{YYYYMMDD-HHMMSS}.md
```

Create `.forge/handoffs/` if it doesn't exist.

```markdown
# Handoff — {project.name}
Created: {timestamp}

## Forge State
- Phase: {phase}
- Current task: {task or "none"}
- Completed tasks: {N}
- Security score: {score}/100{⚠️ CRITICAL FINDINGS: N — run /forge--sec before other work}

## Git State
- Branch: {branch}
- Working tree: {clean / list of N changed files}
- Recent commits:
{last 10 git log --oneline}

## Plan Progress
{N}/{M} tasks complete ({%}) — file: {plan-filename.md}
In progress: {list or "none"}

## Recent File Activity
{last 20 lines from .forge/logs/file-changes.log}

## Agent Docs Staleness
{list any docs older than 14 days, or "all current"}

## Current Focus
{specific description of what was being worked on}

## What's Next
{ordered, actionable list}

## Decisions Made
{decisions with rationale}

## Gotchas
{don't-forget list}
```

---

## Phase 4: Register and Confirm

After writing the handoff file:

1. Write the handoff path (one line, no trailing newline) to `~/.claude/pending-resume`:
   ```bash
   echo -n ".forge/handoffs/handoff-{timestamp}.md" > ~/.claude/pending-resume
   ```
   Use the absolute path so it works from any directory on next session open.

2. Tell the user:
   ```
   ✅ Handoff written: .forge/handoffs/handoff-{timestamp}.md
   ✅ Registered for auto-load on next session open.

   You can now close this session. Open a new one and the handoff will
   inject automatically at the top of the session. Or run /forge--continue
   in this session to review what was captured.
   ```

---

## Rules

- Factual sections come from files and commands. Read them — don't guess from memory.
- If a file doesn't exist, note "not found" — don't skip the section silently.
- Keep it scannable: headers, bullets, short phrases. Not paragraphs.
- The test: could a fresh Claude session read this and know exactly where to start,
  what not to break, and what decisions to honour?
