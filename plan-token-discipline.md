# Implementation Plan: Token Discipline
Spec: spec-token-discipline.md
Status: IN PROGRESS
Created: 2026-02-25
Last Updated: 2026-02-25

---

## Verification Note

Most ACs in this spec are inspection-based — grep for frontmatter, read a file,
validate JSON structure. BUILD mode should NOT scaffold test files for frontmatter
or template content tasks. Use direct inspection (grep, cat, jq) to verify ACs.
The exceptions are shell hook scripts (T004, T005) — those get functional verification
by executing the script in a test directory and asserting file creation and exit code.

---

## Critical Path

Model frontmatter (fastest wins) → Hook rewrites (highest leverage) → Settings wiring
→ Context threshold (highest risk, last)

T001 → T004 → T005 → T006 → T011 → T012

---

## Task Ledger

### T001: Add model frontmatter to commands [COMPLETE 2026-02-26]
Domain: ci
Risk: low
Depends on: none
Requires review: none
Acceptance criteria: AC3.1, AC3.2, AC3.3, AC3.7

Add `model:` to the YAML frontmatter of three command files. Values are aliases only —
`opus`, `sonnet`, `haiku`, `inherit`. Full model IDs are NOT valid.

Files:
- `commands/sec.md` → add `model: opus`
- `commands/plan.md` → add `model: opus`
- `commands/recon.md` → add `model: haiku`

Definition of done:
- [x] `grep -n "model:" commands/sec.md commands/plan.md commands/recon.md` returns
      exactly one match per file with the correct alias
- [x] No file contains a full model ID string (grep for `claude-opus`, `claude-sonnet`,
      `claude-haiku` returns zero hits across commands/ and agents/)

Notes: INSERT the `model:` line into the existing frontmatter block — do not replace or
reformat the entire frontmatter. One line addition per file.

---

### T002: Add model frontmatter to agents
Domain: ci
Risk: low
Depends on: none
Requires review: none
Acceptance criteria: AC3.4, AC3.5, AC3.7

Add or confirm `model:` in the YAML frontmatter of all five agent files.
`code-reviewer.md` already has `model: sonnet` — verify, do not duplicate.

Files:
- `agents/security-reviewer.md` → add `model: opus`
- `agents/code-reviewer.md` → verify `model: sonnet` present (already there, confirm only)
- `agents/performance-reviewer.md` → add `model: sonnet`
- `agents/test-writer.md` → add `model: sonnet`
- `agents/db-explorer.md` → add `model: sonnet`

Definition of done:
- [ ] `grep -n "model:" agents/*.md` returns exactly one match per file
- [ ] security-reviewer.md contains `model: opus`
- [ ] all others contain `model: sonnet`

Notes: Do not add `model: inherit` — explicit sonnet is preferred over inherited default
for auditability. Do not duplicate the existing entry in code-reviewer.md.

---

### T003: Add model selection table to agent_docs/architecture.md [COMPLETE 2026-02-26]
Domain: ci
Risk: low
Depends on: T001, T002 (table documents the decisions made in those tasks)
Requires review: none
Acceptance criteria: AC3.6

Add a "Model Selection" section to `agent_docs/architecture.md` documenting the
rationale for each model assignment. This is the living reference — if model
assignments change, this table changes first.

Files:
- `agent_docs/architecture.md`

The table must include:

| Command / Agent | Model | Rationale |
|---|---|---|
| `/forge--sec` | opus | Security audit requires deep pattern recognition |
| `/forge--plan` | opus | Architecture decisions require multi-step reasoning |
| `/forge--recon` | haiku | Fast first-pass scan — findings refined in follow-on sessions |
| All other commands | sonnet (inherited) | Good cost/quality ratio for implementation work |
| `security-reviewer` agent | opus | Parallel security review needs same depth as /forge--sec |
| All other agents | sonnet | Implementation and review tasks — sonnet sufficient |

Definition of done:
- [x] `grep -n "Model Selection" agent_docs/architecture.md` returns a match
- [x] Table is present with all six rows above (minimum)
- [x] Section explains the alias convention (`opus`/`sonnet`/`haiku`, not full IDs)

Notes: The architecture.md file is currently a template with [FILL IN] sections.
Add the Model Selection section at the bottom without removing the existing template
structure — other sections get populated during project recon on real projects.

---

### T004: Rewrite hooks/session-end.sh
Domain: ci
Risk: medium
Depends on: none
Requires review: none
Acceptance criteria: AC1.1, AC1.2, AC1.6, AC4.3

Full rewrite of session-end.sh. The current version appends placeholder stubs to
claude-progress.txt that Claude never fills in programmatically. Replace with:
1. Machine-readable JSON state written to `.forge/logs/last-session.json`
2. `learn-pending` flag file written to `.forge/logs/learn-pending`
3. Dirty tree warning printed to stdout if uncommitted changes exist
4. Graceful degradation if `jq` is not installed (exit 0, no crash)

Files:
- `hooks/session-end.sh` (full rewrite)

The script receives hook context via stdin as JSON. It must NOT read from stdin
in a way that blocks if nothing is piped. Use `INPUT=$(cat 2>/dev/null)` with
a timeout or default to empty string.

Required output file structure for `.forge/logs/last-session.json`:
```json
{
  "ended_at": "2026-02-25T14:32:01",
  "branch": "main",
  "uncommitted_changes": 3,
  "forge_phase": "build",
  "forge_task": "T003"
}
```

`forge_phase` and `forge_task` read from `.forge/state.json` if it exists, else "unknown"/"none".
`branch` from `git branch --show-current`, else "unknown".
`uncommitted_changes` from `git status --porcelain | wc -l`.

Definition of done:
- [ ] Execute the script in a test git directory: `bash hooks/session-end.sh < /dev/null`
- [ ] `.forge/logs/last-session.json` exists and is valid JSON: `jq . .forge/logs/last-session.json`
- [ ] `.forge/logs/last-session.json` contains all five required fields
- [ ] `.forge/logs/learn-pending` exists (empty file, created by `touch`)
- [ ] Running on a dirty tree prints a warning line containing the change count
- [ ] Running on a machine without jq exits 0 (test with `PATH= bash hooks/session-end.sh`)
- [ ] Script exits 0 in all cases

Notes: The old claude-progress.txt stub-appending behavior is REMOVED entirely.
Do not preserve it. The learn-pending flag is a `touch` — no content, just existence.
Always `mkdir -p .forge/logs` before writing.

---

### T005: Create hooks/pre-compact.sh
Domain: ci
Risk: low
Depends on: none
Requires review: none
Acceptance criteria: AC1.3, AC1.4, AC1.6

New file. Fires at `PreCompact` hook event. Captures working state to
`.forge/logs/pre-compact-state.json` before Claude Code's auto-compaction runs.
Silent — no stdout output (stdout would corrupt the render path).

Files:
- `hooks/pre-compact.sh` (new file)

Required output file structure:
```json
{
  "captured_at": "2026-02-25T14:32:01",
  "branch": "main",
  "uncommitted_changes": 3,
  "recent_files": ["src/blast.js", "lib/graph.js"]
}
```

`recent_files` from `git diff --name-only HEAD 2>/dev/null | head -10` — file paths only,
never file contents. Array may be empty `[]` if git unavailable or tree is clean.

Definition of done:
- [ ] Execute the script: `bash hooks/pre-compact.sh < /dev/null`
- [ ] `.forge/logs/pre-compact-state.json` exists and is valid JSON
- [ ] Contains all four required fields with correct types
- [ ] Runs in a directory without `.forge/logs/` — creates directory, writes file, exits 0
- [ ] Running without jq exits 0 (test with `PATH= bash hooks/pre-compact.sh`)
- [ ] Script produces no stdout output (verify: `output=$(bash hooks/pre-compact.sh); [ -z "$output" ]`)

Notes: `mkdir -p .forge/logs` before writing. All output redirected to /dev/null or
suppressed. This script must never print anything — it runs on the render path.

---

### T006: Update templates/settings.json
Domain: ci
Risk: medium
Depends on: T004, T005
Requires review: none
Acceptance criteria: AC1.5, AC1.7, AC4.4, AC4.5, AC5.7

Four changes to `templates/settings.json` in a single pass:

1. **Remove dead golem hooks** — delete all entries referencing `~/.golem/hooks/*.sh`
   from PreToolUse. `~/.golem/` does not exist; these silently fail on every hook event.
   Entries to remove: `context-handoff.sh`, `block-destructive.sh`, `block-push-main.sh`,
   `version-tag-sync.sh`. Also remove the PostToolUse entry writing to `.golem/logs/`.

2. **Add PreCompact hook** — new top-level key in `hooks`:
   ```json
   "PreCompact": [
     {
       "matcher": "",
       "hooks": [
         {
           "type": "command",
           "command": "if [ -f .claude/hooks/pre-compact.sh ]; then bash .claude/hooks/pre-compact.sh; fi"
         }
       ]
     }
   ]
   ```

3. **Add SessionStart hook for last-session.json** — new entry in the existing
   SessionStart array:
   ```json
   {
     "type": "command",
     "command": "if [ -f .forge/logs/last-session.json ] && command -v jq >/dev/null 2>&1; then ENDED=$(jq -r '.ended_at' .forge/logs/last-session.json); DIRTY=$(jq -r '.uncommitted_changes' .forge/logs/last-session.json); BRANCH=$(jq -r '.branch' .forge/logs/last-session.json); echo \"[CC-Forge] Last session: $ENDED | Branch: $BRANCH | Uncommitted: $DIRTY\"; fi"
   }
   ```

4. **Add SessionStart hook for learn-pending + threshold flag** — new entry in
   existing SessionStart array:
   ```json
   {
     "type": "command",
     "command": "if [ -f .forge/logs/learn-pending ]; then echo \"[CC-Forge] Pattern extraction available from last session. Run /forge--learn when ready.\"; rm -f .forge/logs/learn-pending; fi; rm -f .forge/logs/context-threshold-triggered 2>/dev/null; exit 0"
   }
   ```

Files:
- `templates/settings.json`

Definition of done:
- [ ] `grep -r "golem" templates/settings.json` returns zero hits
- [ ] `jq '.hooks.PreCompact' templates/settings.json` returns a non-null array
- [ ] `jq '.hooks.SessionStart | length' templates/settings.json` is greater than
      the pre-change count (new entries added)
- [ ] `jq . templates/settings.json` exits 0 (valid JSON throughout)
- [ ] The `.golem/logs/file-changes.log` PostToolUse write is removed or changed
      to `.forge/logs/file-changes.log`

Notes: Read the full current file before editing. Do not accidentally remove the
existing legitimate hooks (forge state display, security score display, progress file).
Validate JSON after every edit. The golem log write in PostToolUse should be changed
to `.forge/logs/file-changes.log`, not deleted — the logging behavior is useful.

---

### T007: Create templates/agent-handoff.md
Domain: ci
Risk: low
Depends on: none
Requires review: none
Acceptance criteria: AC2.1, AC2.2, AC2.6

New template file. This is the schema contract for inter-agent handoffs in the
build pipeline. Must be distinct from session handoffs (`handoff-*.md`) — uses
`agent-` prefix per the naming convention already defined in the spec.

Files:
- `templates/agent-handoff.md` (new file)

Required structure (BUILD mode should implement this exactly):

```markdown
## FORGE AGENT HANDOFF
From: {AGENT_NAME}
To: {NEXT_AGENT}
Timestamp: {ISO8601}
Plan: {plan-file.md | none}
Task: {TASK_ID | none}

### Context
{1-3 sentences: what was this agent's scope and what did it establish?}

### Findings
{Bulleted list of key discoveries, constraints, decisions made}

### Files Modified
{Repo-relative paths — empty list if read-only agent}

### Open Questions
{Items the receiving agent must resolve — empty list if none}

### Recommendations
{Specific actionable direction for the next agent}

### Signal
```json
{
  "from": "{AGENT_NAME}",
  "to": "{NEXT_AGENT}",
  "task_id": "{TASK_ID or null}",
  "status": "complete",
  "files_modified": [],
  "open_questions": 0,
  "blocking": false
}
```
<!-- status valid values: "complete" | "partial" | "blocked" -->
```

Definition of done:
- [ ] File exists at `templates/agent-handoff.md`
- [ ] Contains all required sections: From, To, Timestamp, Plan, Task, Context,
      Findings, Files Modified, Open Questions, Recommendations, Signal
- [ ] Signal block contains all required fields: from, to, task_id, status,
      files_modified, open_questions, blocking
- [ ] Comment documents the three valid status values
- [ ] `ls .forge/handoffs/agent-*.md` naming would NOT match `ls .forge/handoffs/handoff-*.md`
      (globs are distinct — verify by inspection)

---

### T008: Update commands/build.md — inter-agent handoff emission
Domain: ci
Risk: medium
Depends on: T007
Requires review: none
Acceptance criteria: AC2.3, AC2.4

Add a "Task Completion — Emit Agent Handoff" section to `commands/build.md`.
This instructs BUILD mode to write an inter-agent handoff to `.forge/handoffs/`
after each task completes. The handoff is in addition to, not instead of, the
existing JSON Signal already emitted by build.md.

Files:
- `commands/build.md`

The new section should be inserted BEFORE the "Emit JSON Signal" section and
should instruct Claude to:
1. Write `.forge/handoffs/agent-{TASK_ID}-{YYYYMMDD-HHMMSS}.md` using the
   template at `templates/agent-handoff.md`
2. If status is `blocked`: populate Open Questions, set `blocking: true`,
   and state explicitly that the build loop halts — do NOT proceed to the
   next task
3. If status is `partial`: log a warning and continue to next task

Definition of done:
- [ ] `grep -n "agent-handoff" commands/build.md` returns at least one match
- [ ] `grep -n "blocked" commands/build.md` returns a match in the new section
      stating the loop halts on blocked status
- [ ] The new section references `templates/agent-handoff.md` by name
- [ ] The existing "Emit JSON Signal" section is unchanged

Notes: Do not change the existing JSON signal schema — the agent handoff is a
separate Markdown file. The build loop reads the JSON signal; the agent handoff
is for the receiving agent (human or next Claude session) to orient from.

---

### T009: Update commands/continue.md — agent handoff detection
Domain: ci
Risk: medium
Depends on: T007
Requires review: none
Acceptance criteria: AC2.5

Add logic to `commands/continue.md` Step 1 (Find the Handoff) to detect and
handle inter-agent handoffs (`agent-*.md`) alongside session handoffs (`handoff-*.md`).

Files:
- `commands/continue.md`

Add to Step 1 after the existing handoff detection:

```markdown
**Also check for blocked inter-agent handoffs:**
```bash
ls -t .forge/handoffs/agent-*.md 2>/dev/null | head -1
```
If an `agent-*.md` file exists AND its Signal block contains `"blocking": true`:
- Surface it BEFORE the session handoff SITREP
- Display: "⚠ BLOCKED BUILD: Task {task_id} is waiting for operator input."
- Show the Open Questions section
- Ask: "Resolve this blocker before resuming, or continue with session handoff?"
- Do NOT proceed with either until operator responds

If an `agent-*.md` file exists but `"blocking": false`: note it in the SITREP
as recent task activity but do not interrupt the resume flow.
```

Definition of done:
- [ ] `grep -n "agent-\*" commands/continue.md` returns at least one match
- [ ] `grep -n "blocking" commands/continue.md` returns a match in the new section
- [ ] The existing session handoff detection logic (handoff-*.md, pending-resume)
      is completely unchanged — read the full file before editing, verify after
- [ ] New logic is added to Step 1 only, no other steps modified

Notes: This is the highest-risk edit in the plan. Read commands/continue.md in
full before touching it. The existing resume flow is working — surgical addition only.

---

### T010: Create commands/learn.md
Domain: ci
Risk: low
Depends on: none
Requires review: none
Acceptance criteria: AC4.1, AC4.2, AC4.6

New command file. Session pattern extraction — analyzes the current session for
non-trivial solutions and writes structured skill files to the project memory directory.

Files:
- `commands/learn.md` (new file)

Required content:
- YAML frontmatter: description, allowed-tools (Read, Write, Glob, Bash)
- Extraction criteria: what to SKIP (simple edits, already documented, already in skills),
  what to EXTRACT (multi-step solutions requiring reasoning, non-obvious config patterns,
  cross-component interactions, project-specific gotchas found empirically)
- Security instruction: EXPLICITLY state do not write credentials, tokens, connection
  strings, file contents, or env variable values. Patterns describe HOW, not WHAT values.
- Output path: `~/.claude/projects/$(pwd | tr '/' '-')/memory/learned-{slug}.md`
  (matches Claude Code's convention — same dir as MEMORY.md)
- Required fields per learned file: `Extracted` (date), `Confidence` (high/medium/low),
  `Context`, `Pattern`, `When to Apply`, `Steps`, `Why This Works`, `Source`
- MEMORY.md housekeeping: check line count, if > 180 archive to
  `memory/archive-{YYYY-MM-DD}.md`, add only single-line summary reference per pattern

Definition of done:
- [ ] File exists at `commands/learn.md`
- [ ] Frontmatter present with description and allowed-tools
- [ ] Contains explicit "do not extract" list including credentials/tokens
- [ ] Target path uses `$(pwd | tr '/' '-')` pattern, not `{hash}`
- [ ] All eight required fields listed for learned file format
- [ ] MEMORY.md housekeeping instructions present with 180-line threshold

---

### T011: Create context-handoff.sh and wire into global install
Domain: ci
Risk: medium
Depends on: none
Requires review: none
Acceptance criteria: AC5.5, AC5.6, AC5.8

Create the background handoff script invoked by the statusline threshold trigger.
This script runs detached from the statusline render path — it must be completely
silent (all output to /dev/null) and must exit 0 in all circumstances.

**Source file location**: The script must live in the cc-forge package so it is
installed during `install.sh --global`. Add it to `hooks/context-handoff.sh`
(installed to `~/.claude/forge/context-handoff.sh` by the global installer).
Also update `install.sh` to copy it to the correct global location.

Files:
- `hooks/context-handoff.sh` (new file in package)
- `install.sh` (add copy step for context-handoff.sh to global install path)

The script must:
1. Determine the current project directory (`$PWD`)
2. Create `.forge/handoffs/` if it does not exist
3. Write a minimal handoff file to `.forge/handoffs/handoff-$(date +%Y%m%d-%H%M%S).md`
   containing: timestamp, branch, uncommitted count, forge phase/task if available,
   and a note that this was triggered automatically by context threshold
4. Write the absolute handoff path to `~/.claude/pending-resume`
5. Exit 0 in all cases — never fail loudly

The `CONTEXT_THRESHOLD` variable (default `70`) must be defined at the top of
`statusline.sh` (not in this script) — AC5.8 places the configurable threshold
in the statusline. This script does not need to know the threshold.

Definition of done:
- [ ] `hooks/context-handoff.sh` exists and is executable (`chmod +x`)
- [ ] Running `bash hooks/context-handoff.sh` in a git directory creates
      `.forge/handoffs/handoff-*.md` and writes `~/.claude/pending-resume`
- [ ] Script produces zero stdout/stderr output: `output=$(bash hooks/context-handoff.sh 2>&1); [ -z "$output" ]`
- [ ] Script exits 0 when `.forge/` does not exist (creates it)
- [ ] `install.sh` `--global` path includes a step to copy/symlink `context-handoff.sh`
      to `~/.claude/forge/context-handoff.sh`
- [ ] `grep "context-handoff" install.sh` returns a match

Notes: The handoff written by this script is intentionally minimal — it captures
state, not context. The full session state was captured by session-end.sh. This
script's job is just to register a pending-resume so the next session auto-loads it.

---

### T012: Modify statusline.sh — context threshold detection
Domain: ci
Risk: high
Depends on: T011
Requires review: none
Acceptance criteria: AC5.1, AC5.2, AC5.3, AC5.4, AC5.7, AC5.8, AC5.9

**Highest-risk task.** The statusline script renders on every tick. Any blocking
call, unhandled error, or malformed output corrupts the status bar for the entire
session. All new code paths must be wrapped defensively.

**First: locate the source file.** The statusline is at `~/.claude/statusline.sh`.
Verify whether this is a symlink to the cc-forge package or a standalone file:
```bash
ls -la ~/.claude/statusline.sh
```
If it is a symlink to the package, edit the package source. If it is a standalone
file not in the package, it must be added to the package and install.sh updated
to install it.

Files:
- `~/.claude/statusline.sh` (or its package source — verify first)

Changes:
1. **Define threshold variable** at the top of the script (after color definitions):
   ```bash
   CONTEXT_THRESHOLD=70
   ```

2. **Parse used_percentage from stdin** — the statusline receives JSON on stdin.
   The current script does NOT read from stdin at all (it reads from cache files).
   Add stdin parsing at the top:
   ```bash
   STATUSLINE_INPUT=$(cat 2>/dev/null)
   CONTEXT_PCT=""
   if [ -n "$STATUSLINE_INPUT" ] && command -v jq >/dev/null 2>&1; then
     CONTEXT_PCT=$(echo "$STATUSLINE_INPUT" | jq -r '.context_window.used_percentage // empty' 2>/dev/null)
   fi
   ```

3. **Threshold detection and trigger** — after stdin parsing:
   ```bash
   CONTEXT_WARNING=""
   if [ -n "$CONTEXT_PCT" ] && [ "$CONTEXT_PCT" -ge "$CONTEXT_THRESHOLD" ] 2>/dev/null; then
     CONTEXT_WARNING=" ${YELLOW}⚠ CTX ${CONTEXT_PCT}%%${NC}"
     if [ ! -f ".forge/logs/context-threshold-triggered" ]; then
       mkdir -p .forge/logs 2>/dev/null
       touch .forge/logs/context-threshold-triggered 2>/dev/null
       (nohup ~/.claude/forge/context-handoff.sh >/dev/null 2>&1 &)
     fi
   fi
   ```

4. **Add `$CONTEXT_WARNING` to the status bar output** — append to Line 1 of the
   existing printf output so it appears inline with forge version, time, project, git.

Definition of done:
- [ ] `grep -n "CONTEXT_THRESHOLD" ~/.claude/statusline.sh` returns a match at the top
- [ ] `grep -n "used_percentage" ~/.claude/statusline.sh` returns a match
- [ ] `grep -n "context-threshold-triggered" ~/.claude/statusline.sh` returns a match
- [ ] `grep -n "context-handoff.sh" ~/.claude/statusline.sh` returns a match
- [ ] Simulate threshold crossing: create `.forge/logs/` dir, then run
      `echo '{"context_window":{"used_percentage":75}}' | bash ~/.claude/statusline.sh`
      and verify: warning appears in output, trigger file created, no errors
- [ ] Simulate re-trigger: run again — verify trigger fires only ONCE (flag file blocks it)
- [ ] Simulate below threshold: `echo '{"context_window":{"used_percentage":50}}' | bash ...`
      — verify no warning, no trigger, no flag file
- [ ] Simulate no stdin: `bash ~/.claude/statusline.sh < /dev/null` — exits 0, renders
      normally, no warning (graceful degradation when context data absent)
- [ ] The existing statusline output (forge version, git, rate limits) is unchanged

Notes: The integer comparison `[ "$CONTEXT_PCT" -ge "$CONTEXT_THRESHOLD" ]` will error
if CONTEXT_PCT is empty or non-numeric. The `2>/dev/null` on the comparison suppresses
this — but also add a numeric guard: `[[ "$CONTEXT_PCT" =~ ^[0-9]+$ ]]` before comparing.
Wrap ALL new code in error-suppressed blocks. A broken statusline is a bad developer
experience on every single turn.

---

## Dependency Graph

```
T001 ─────────────────────────────────────┐
T002 ─────────────────────────────────────┤→ T003
T004 ──────────────────────────────────┐  │
T005 ──────────────────────────────────┤→ T006
T007 ──────────────────────────────┐   │
                                   ├→ T008
                                   └→ T009
T010 (no deps, no dependents — standalone)
T011 ──────────────────────────────────────→ T012
```

Tasks with no dependencies (can start immediately, in parallel):
T001, T002, T004, T005, T007, T010, T011

---

## Risk Register

| Task | Risk | Mitigation |
|------|------|------------|
| T006 | Removing golem hooks may leave a gap if golem is reinstalled later | Document removal in commit message; golem re-install will re-add its own hooks |
| T006 | JSON edit to settings.json could break hook wiring if malformed | Validate with `jq .` after every edit; read full file before touching |
| T009 | Adding branch to continue.md could break existing session resume | Read full file first; add to Step 1 only; verify existing logic unchanged after edit |
| T012 | Blocking call in statusline freezes status bar for entire session | All new code paths wrapped in `2>/dev/null`; stdin read non-blocking; integer guard on comparison |
| T012 | statusline.sh may not be in cc-forge package — may be a standalone file | Verify symlink status first (`ls -la ~/.claude/statusline.sh`) before editing |

---

## Rollback Plan

All changes are to configuration files and shell scripts — no database migrations,
no deployed services, no compiled artifacts.

**Per-task rollback:**
- T001–T003: Remove `model:` line from frontmatter. One-line revert.
- T004–T005: Restore previous hook content from git. `git checkout hooks/session-end.sh`
- T006: Restore settings.json from git. `git checkout templates/settings.json`
- T007–T010: Delete the new files. `git rm templates/agent-handoff.md commands/learn.md`
- T008–T009: Restore from git. `git checkout commands/build.md commands/continue.md`
- T011: Delete hook file, revert install.sh. `git checkout install.sh`
- T012: Restore statusline from git (if in package) or restore from backup.

**Pre-T012 backup:** Before editing statusline.sh, create a backup:
```bash
cp ~/.claude/statusline.sh ~/.claude/statusline.sh.bak
```
If statusline breaks: `cp ~/.claude/statusline.sh.bak ~/.claude/statusline.sh`

---

## Out of Scope (carry forward)

- Pare MCP server integration — next spec, this plan is the prerequisite
- `forge status --json` / dual output for CLI commands — separate spec
- Structured error taxonomy / `lib/errors.js` — requires Node.js CLI layer
- Cross-editor adapters (Cursor, Codex, OpenCode)
- Lowering `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE` from 85 — consider after T012 is
  live and the two-layer threshold system is validated in practice
