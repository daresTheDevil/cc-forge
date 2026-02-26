# Spec: Token Discipline — Hook Automation, Handoff Schema, Model Selection, Pattern Extraction, Proactive Context Management
Status: APPROVED
Created: 2026-02-25
Author: David
Related discuss artifact: docs/borrowed-patterns.md

---

## Problem Statement

Every Claude Code session burns tokens re-orienting to project state, re-parsing
unstructured hook output, defaulting heavyweight models to lightweight tasks, and
rediscovering solutions that were already found in previous sessions. When sessions
run long, context window compaction introduces a further cost: Claude loses coherence
mid-task and has to rebuild orientation from a lossy auto-summary it didn't author.
CC-Forge has the hooks, commands, and agent infrastructure to address all five failure
modes — but the current implementations are stubs, templates, or absent. This spec
defines the work to close those gaps, with token cost reduction as the primary success
criterion and a clean foundation for a follow-on Pare MCP integration.

---

## Scope

### In Scope
- Rewrite `hooks/session-end.sh` to write machine-readable state instead of placeholder stubs
- Add `hooks/pre-compact.sh` to capture working state before context window auto-compaction
- Update `templates/settings.json` to wire `PreCompact` hook and improve `SessionStart`
- Clean up dead `~/.golem/` hook references in `templates/settings.json` (golem dir does not exist; these silently fail on every hook event)
- Create `templates/agent-handoff.md` — structured inter-agent handoff with JSON Signal block
- Update `commands/build.md` to emit inter-agent handoffs after each task
- Update `commands/continue.md` to distinguish session handoffs vs. inter-agent handoffs
- Add `model:` frontmatter to `commands/sec.md`, `commands/plan.md`, `commands/recon.md`
- Add model selection rationale table to `agent_docs/architecture.md`
- Audit and update model assignment in all five files in `agents/`
- Create `commands/learn.md` — session pattern extraction command
- Update `hooks/session-end.sh` to write `learn-pending` flag
- Update `templates/settings.json` `SessionStart` to surface learn-pending notification
- Add proactive context threshold detection to `~/.claude/statusline.sh` — at 70% usage, automatically trigger handoff and register `pending-resume` in the background
- Add `~/.claude/forge/context-handoff.sh` — the background script invoked by the statusline threshold trigger
- Update `templates/settings.json` `SessionStart` to clear the threshold-triggered flag on new session open

### Out of Scope
- Pare MCP server integration (next phase — this work is the prerequisite)
- `forge status --json` / dual output flag on CLI commands (separate spec)
- Structured error taxonomy / `lib/errors.js` (requires Node.js CLI layer, separate work)
- Cross-editor adapters (Cursor, Codex, OpenCode)
- Changes to the build loop shell script (`loops/build.sh`) beyond what `commands/build.md` instructs

---

## Acceptance Criteria

Each criterion is independently testable. Format: GIVEN / WHEN / THEN.

### Feature 1 — Hook Automation Templates

**AC1.1 — session-end writes machine-readable state**
GIVEN a project with CC-Forge initialized
WHEN a Claude Code session ends (Stop hook fires)
THEN `.forge/logs/last-session.json` exists and contains valid JSON with fields:
`ended_at` (ISO8601), `branch` (string), `uncommitted_changes` (integer), `forge_phase` (string), `forge_task` (string)

**AC1.2 — session-end warns on dirty tree**
GIVEN a project with uncommitted changes
WHEN a Claude Code session ends
THEN the hook prints a warning message containing the count of uncommitted changes to stdout

**AC1.3 — pre-compact hook exists and captures state**
GIVEN a project with CC-Forge initialized
WHEN the `PreCompact` hook fires
THEN `.forge/logs/pre-compact-state.json` exists and contains valid JSON with fields:
`captured_at` (ISO8601), `branch` (string), `uncommitted_changes` (integer), `recent_files` (array)

**AC1.4 — pre-compact hook fails gracefully**
GIVEN a project directory where `.forge/logs/` does not exist
WHEN the `PreCompact` hook fires
THEN the hook creates the directory and writes the file without error, exits 0

**AC1.5 — SessionStart surfaces last session state**
GIVEN `.forge/logs/last-session.json` exists from a previous session
WHEN a new Claude Code session opens (SessionStart fires)
THEN the hook prints a single-line summary containing: last ended_at timestamp, branch name, and uncommitted_changes count

**AC1.6 — hooks degrade gracefully without jq**
GIVEN a machine where `jq` is not installed
WHEN session-end.sh or pre-compact.sh runs
THEN the hook exits 0 without error (no crash, no broken pipe)

**AC1.7 — PreCompact is wired in templates/settings.json**
GIVEN `templates/settings.json`
WHEN inspected
THEN a `PreCompact` key exists in the `hooks` object with a command entry that invokes `pre-compact.sh`

### Feature 2 — Orchestration Handoff Schema

**AC2.1 — agent-handoff template exists with all required sections**
GIVEN `templates/agent-handoff.md`
WHEN inspected
THEN it contains all of: `From:`, `To:`, `Timestamp:`, `Context`, `Findings`, `Files Modified`, `Open Questions`, `Recommendations`, and a fenced `Signal` JSON block with fields `from`, `to`, `task_id`, `status`, `files_modified`, `open_questions`, `blocking`

**AC2.2 — Signal block status values are constrained**
GIVEN the `Signal` JSON block in `templates/agent-handoff.md`
WHEN inspected
THEN the `status` field comment documents exactly three valid values: `complete`, `partial`, `blocked`

**AC2.3 — build.md instructs handoff emission after each task**
GIVEN `commands/build.md`
WHEN inspected
THEN it contains a section instructing Claude to write an inter-agent handoff to
`.forge/handoffs/agent-{TASK_ID}-{timestamp}.md` after task completion, using the template

**AC2.4 — build.md instructs blocked signal to halt the loop**
GIVEN `commands/build.md`
WHEN inspected
THEN it explicitly states that a `status: "blocked"` Signal stops the build loop and surfaces the blocking question to the operator

**AC2.5 — continue.md distinguishes session vs. agent handoffs**
GIVEN `commands/continue.md`
WHEN inspected
THEN it contains logic to distinguish `handoff-*.md` (session handoffs) from `agent-*.md` (inter-agent handoffs) and instructs Claude to surface a blocked `agent-*.md` before proceeding if one is newer than the most recent session handoff

**AC2.6 — agent handoff files do not conflict with session handoff filenames**
GIVEN the naming convention `agent-{TASK_ID}-{timestamp}.md` for inter-agent handoffs
WHEN compared to the session handoff naming convention `handoff-{YYYYMMDD-HHMMSS}.md`
THEN the prefixes are distinct — no glob pattern that matches one matches the other

### Feature 3 — Model Selection Mapping

**AC3.1 — sec.md specifies opus**
GIVEN `commands/sec.md`
WHEN inspected
THEN the YAML frontmatter contains `model: opus`

**AC3.2 — plan.md specifies opus**
GIVEN `commands/plan.md`
WHEN inspected
THEN the YAML frontmatter contains `model: opus`

**AC3.3 — recon.md specifies haiku**
GIVEN `commands/recon.md`
WHEN inspected
THEN the YAML frontmatter contains `model: haiku`

**AC3.4 — security-reviewer agent specifies opus**
GIVEN `agents/security-reviewer.md`
WHEN inspected
THEN the YAML frontmatter contains `model: opus`

**AC3.5 — remaining agents explicitly specify sonnet**
GIVEN `agents/code-reviewer.md`, `agents/performance-reviewer.md`, `agents/test-writer.md`, `agents/db-explorer.md`
WHEN inspected
THEN each contains `model: sonnet` in frontmatter (explicit is better than inherited for auditability; `code-reviewer.md` already has this)

**AC3.6 — architecture.md contains model selection table**
GIVEN `agent_docs/architecture.md`
WHEN inspected
THEN it contains a "Model Selection" section with a table mapping command/agent types to model names with rationale

**AC3.7 — all model values use supported aliases**
GIVEN all files in `commands/` and `agents/` with `model:` frontmatter
WHEN inspected
THEN all values are one of the four supported aliases: `opus`, `sonnet`, `haiku`, `inherit`
(Full model IDs like `claude-opus-4-6` are NOT used — Claude Code frontmatter uses aliases only)

### Feature 4 — Session Pattern Extraction (forge learn)

**AC4.1 — commands/learn.md exists with correct extraction criteria**
GIVEN `commands/learn.md`
WHEN inspected
THEN it contains: extraction criteria (what to skip, what to extract), output format specification, target path `~/.claude/projects/{hash}/memory/learned-{slug}.md`, and the required fields: `Extracted`, `Confidence`, `Context`, `Pattern`, `When to Apply`, `Steps`, `Why This Works`, `Source`

**AC4.2 — learned skill files are written to the correct path**
GIVEN `commands/learn.md`
WHEN inspected
THEN the target write path is `~/.claude/projects/$(pwd | tr '/' '-')/memory/` — the project
path with `/` replaced by `-`, matching Claude Code's own convention (e.g. `/Users/dkay/code/cc-forge`
→ `~/.claude/projects/-Users-dkay-code-cc-forge/memory/`). Not the project directory itself,
not a global skills directory that would mix projects.

**AC4.3 — session-end.sh writes learn-pending flag**
GIVEN a project with CC-Forge initialized
WHEN a Claude Code session ends (Stop hook fires)
THEN `.forge/logs/learn-pending` is created (touch, not written with content)

**AC4.4 — SessionStart surfaces learn-pending notification**
GIVEN `.forge/logs/learn-pending` exists
WHEN a new Claude Code session opens
THEN the SessionStart hook prints a message indicating a pattern extraction pass is available and removes the flag file

**AC4.5 — learn-pending flag is non-blocking**
GIVEN `.forge/logs/learn-pending` exists
WHEN SessionStart hook runs and surfaces the notification
THEN the hook exits 0 and does not prevent the session from opening normally

**AC4.6 — commands/learn.md instructs MEMORY.md housekeeping**
GIVEN `commands/learn.md`
WHEN inspected
THEN it contains instructions to: check MEMORY.md line count, archive to `memory/archive-{date}.md` if over 180 lines, and add only a single-line summary reference per pattern (not the full content)

### Feature 5 — Proactive Context Threshold Management

**AC5.1 — statusline.sh reads used_percentage from stdin**
GIVEN `~/.claude/statusline.sh`
WHEN inspected
THEN it parses `context_window.used_percentage` from the JSON payload received on stdin
(the statusline already receives this field per Claude Code's statusline API)

**AC5.2 — threshold trigger fires once per session at 70%**
GIVEN a Claude Code session where context usage crosses 70%
WHEN the statusline script executes and reads `used_percentage >= 70`
THEN it spawns `context-handoff.sh` in the background (non-blocking, `nohup ... &`)
AND writes `.forge/logs/context-threshold-triggered` to prevent re-triggering on
subsequent statusline ticks in the same session

**AC5.3 — threshold trigger does not re-fire after first activation**
GIVEN `.forge/logs/context-threshold-triggered` exists
WHEN the statusline executes again with `used_percentage >= 70`
THEN the background handoff is NOT spawned again — no duplicate handoffs per session

**AC5.4 — statusline displays prominent warning after threshold**
GIVEN context usage has crossed 70%
WHEN the statusline renders
THEN it displays a visible threshold warning (e.g. `⚠ CTX 74%`) in the status bar
in addition to triggering the background handoff — the warning persists until session end

**AC5.5 — context-handoff.sh writes a complete handoff and registers pending-resume**
GIVEN `~/.claude/forge/context-handoff.sh` is invoked
WHEN it runs
THEN it writes a handoff file to `.forge/handoffs/handoff-{YYYYMMDD-HHMMSS}.md`
AND writes the absolute path to `~/.claude/pending-resume`
AND exits 0 regardless of git state or forge state availability

**AC5.6 — context-handoff.sh is non-blocking and silent**
GIVEN the script is spawned from the statusline render path
WHEN it runs
THEN all output is redirected to `/dev/null` — no stdout/stderr that would corrupt
the statusline render, and no blocking wait that would freeze the status bar

**AC5.7 — threshold flag is cleared on SessionStart**
GIVEN `.forge/logs/context-threshold-triggered` exists from a previous session
WHEN a new Claude Code session opens
THEN the SessionStart hook deletes the flag file so the threshold can fire again
in the new session

**AC5.8 — threshold is configurable**
GIVEN `~/.claude/forge/context-handoff.sh`
WHEN inspected
THEN the threshold value (default `70`) is defined as a variable at the top of the
statusline script, not hardcoded inline, so it can be changed without hunting through logic

**AC5.9 — PreCompact hook remains as safety net**
GIVEN the proactive threshold fires at 70% AND `CLAUDE_AUTOCOMPACT_PCT_OVERRIDE=85`
WHEN both are active
THEN the two-layer system operates: statusline trigger at 70% (while Claude is coherent),
PreCompact hook at 85% as a fallback if the session continues past the threshold

---

## Security Considerations

**Session state files contain git metadata**
`last-session.json` and `pre-compact-state.json` include branch names and changed file
paths. These are written to `.forge/logs/` which is gitignored. Confirm `.gitignore`
excludes `.forge/` — if a project's `.gitignore` is misconfigured, session metadata
could be committed. `forge init` should verify `.forge/` is ignored.

**Pattern extraction must not capture secrets**
`commands/learn.md` must explicitly instruct Claude not to write credentials, tokens,
connection strings, file contents, or environment variable values into learned pattern
files. Patterns describe *how* to solve problems, not *what values* were used. A leaked
API key in a skill file that syncs across sessions is a material security risk.

**pre-compact.sh reads git diff output**
`git diff --name-only` returns file paths only — not content. This is safe. The hook
must not be modified to capture `git diff` (content) or `git show` without an explicit
security review.

**Agent handoff files are Markdown with embedded JSON**
The Signal block is author-controlled content in `.forge/handoffs/` (gitignored). No
user input flows into it. Prompt injection risk is low but `commands/continue.md` should
instruct Claude to validate the Signal JSON structure before acting on `status: "blocked"`
— an invalid or malformed signal should surface a warning, not crash the loop.

**Hook execution surface**
All new hooks run at `Stop`, `PreCompact`, and `SessionStart` — they execute shell
commands automatically. They must: use quoted variables, never eval user-controlled
strings, and always exit 0 (a failing hook that exits non-zero can block session startup
or shutdown). Every hook must be audited for the flag injection patterns documented in
`docs/borrowed-patterns.md` Pattern 1.

**Model aliases in frontmatter**
Claude Code frontmatter uses aliases (`opus`, `sonnet`, `haiku`, `inherit`) not full
model IDs. An invalid alias silently falls back to the default model. AC3.7 guards
against this at spec time; runtime validation is outside this scope.

---

## Data Flow Changes

**New data flows introduced:**

```
Session end
  → hooks/session-end.sh
  → .forge/logs/last-session.json    (new — machine-readable state)
  → .forge/logs/learn-pending        (new — flag file)

Session start
  → templates/settings.json SessionStart hook
  → reads .forge/logs/last-session.json → surfaces summary
  → reads .forge/logs/learn-pending → surfaces notification + deletes flag

Context window auto-compaction
  → hooks/pre-compact.sh             (new)
  → .forge/logs/pre-compact-state.json  (new)

Build loop task completion
  → commands/build.md instructs Claude
  → .forge/handoffs/agent-{TASK_ID}-{timestamp}.md  (new)

/forge--learn invocation
  → commands/learn.md instructs Claude
  → ~/.claude/projects/$(pwd | tr '/' '-')/memory/learned-{slug}.md  (new)

Context usage crosses 70% threshold
  → ~/.claude/statusline.sh detects used_percentage >= 70
  → spawns ~/.claude/forge/context-handoff.sh in background (nohup)
  → context-handoff.sh writes .forge/handoffs/handoff-{timestamp}.md
  → context-handoff.sh writes ~/.claude/pending-resume
  → statusline.sh writes .forge/logs/context-threshold-triggered (dedupe flag)
  → statusline displays ⚠ CTX N% warning

Session start (after threshold-triggered session)
  → SessionStart hook deletes .forge/logs/context-threshold-triggered
  → SessionStart hook reads ~/.claude/pending-resume → injects handoff automatically
```

Upstream dependencies affected: none (all new outputs)
Downstream dependencies affected:
- `commands/continue.md` reads `.forge/handoffs/` — now must handle `agent-*.md` files
- `templates/settings.json` SessionStart — reads two new files

---

## Blast Radius Estimate

Domains touched: `ci` (hooks), `session management` (handoffs, learn)
Files changed:
- `hooks/session-end.sh` — modified
- `hooks/pre-compact.sh` — created
- `templates/settings.json` — modified (PreCompact wired, SessionStart improved)
- `templates/agent-handoff.md` — created
- `commands/build.md` — modified
- `commands/continue.md` — modified
- `commands/learn.md` — created
- `commands/sec.md` — frontmatter only
- `commands/plan.md` — frontmatter only
- `commands/recon.md` — frontmatter only
- `agents/security-reviewer.md` — frontmatter only
- `agents/code-reviewer.md` — frontmatter only
- `agents/performance-reviewer.md` — frontmatter only
- `agents/test-writer.md` — frontmatter only
- `agents/db-explorer.md` — frontmatter only
- `agent_docs/architecture.md` — modified (model selection section added)
- `~/.claude/statusline.sh` — modified (context threshold detection, warning display)
- `~/.claude/forge/context-handoff.sh` — created (background handoff script)

Estimated severity: **medium**
Justification: No new external dependencies. No logic changes to existing working commands
beyond `build.md` and `continue.md` additions. Hook changes are additive — new output
files, not changed inputs. Model frontmatter is low-risk (worst case: typo causes fallback
to default model). Two higher-risk changes: `commands/continue.md` has a single handoff
detection path that must not break when the second branch is added; and `statusline.sh`
is a global file that renders on every tick — any blocking call or unhandled error in the
threshold logic will freeze the status bar, so the new code path must be fast, silent,
and defensive.

---

## Technical Approach

All changes are in the cc-forge package's configuration layer — Markdown command files,
shell hooks, JSON templates, and the global statusline script. No new npm dependencies.
No build step required. The five features are independent and can be implemented in any
order. Recommended sequence: (1) model selection mapping — lowest risk, fastest to verify,
grep-checkable; (2) hook automation templates — highest per-session leverage; (3) golem
cleanup in templates/settings.json — quick wins, removes silent failures; (4) orchestration
handoff schema and learn command — additive new files with no existing behavior to break;
(5) proactive context threshold — last, because it modifies the global statusline.sh and
requires careful non-blocking implementation.

---

## Open Questions

All open questions resolved pre-BUILD:

- **Q1: PreCompact hook availability** — ✅ CONFIRMED. Claude Code supports `PreCompact`.
  Wire it in `templates/settings.json`.

- **Q2: Project path derivation for learn output** — ✅ CONFIRMED. Not a hash — it is
  the absolute project path with `/` replaced by `-`. Example: `/Users/dkay/code/cc-forge`
  → `~/.claude/projects/-Users-dkay-code-cc-forge/memory/`. This is the same directory
  where `MEMORY.md` already lives. Use `$(pwd | tr '/' '-')` in the command.

- **Q3: `model:` frontmatter in commands/** — ✅ CONFIRMED. Works in both `commands/`
  and `agents/`. Accepted values are aliases only: `opus`, `sonnet`, `haiku`, `inherit`.
  Full model IDs (e.g. `claude-opus-4-6`) are not valid in frontmatter.

- **Q4: Golem hook cleanup** — ✅ IDENTIFIED. `~/.golem/` does not exist on this machine.
  All `~/.golem/hooks/*.sh` references in `templates/settings.json` are dead and silently
  fail on every matching hook event. Remove them in the same pass as the PreCompact wiring.

---

## Definition of Done

- [ ] All 32 ACs have a corresponding test or verifiable check (grep/inspect is acceptable
      for frontmatter and template content ACs; functional test for hook ACs)
- [ ] Security considerations reviewed — pattern extraction section confirmed to instruct
      against secret capture
- [ ] `.forge/` confirmed gitignored in `install.sh --project` path
- [ ] `agent_docs/architecture.md` updated with model selection table
- [ ] Coherence registry updated if new entities are added (no new registry entities
      expected — this is tooling, not system architecture)
- [ ] `docs/borrowed-patterns.md` updated to mark implemented patterns complete
- [ ] PR reviewed and approved
