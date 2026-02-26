---
description: Session pattern extraction. Analyzes the current session for non-trivial solutions and writes structured skill files to the project memory directory. Run after a productive session to capture hard-won knowledge before it is lost.
allowed-tools: Read, Write, Glob, Bash
---

# CC-Forge: LEARN — Session Pattern Extraction

You are extracting reusable patterns from the current session. Goal: write structured
skill files that let a future session skip the discovery phase and apply proven solutions
directly.

This is a curation pass, not a dump. Quality over quantity — one well-structured pattern
is worth more than ten vague notes.

---

## Step 1: Identify Candidates

Scan the current session for moments where you had to reason through something
non-trivial. Consider:

### What to SKIP — do NOT extract these:

- Simple one-line edits or obvious fixes (adding a missing semicolon, renaming a variable)
- Things already documented in `agent_docs/`, `skills/`, or `MEMORY.md`
- Things already covered by an existing skill file in `~/.claude/forge/skills/`
- Generic programming knowledge (how to write a for loop, standard library usage)
- Anything that required only one obvious step to resolve
- Credentials, tokens, API keys, connection strings, passwords, or env variable values —
  **NEVER extract secrets or sensitive values. Patterns describe HOW, not WHAT values.**

### What to EXTRACT — these are worth capturing:

- Multi-step solutions that required non-obvious reasoning to arrive at
- Non-obvious configuration patterns that took trial and error to discover
- Cross-component interactions: where a change in A required knowing about B and C
- Project-specific gotchas found empirically (not in any docs, discovered by doing)
- Failure modes that were non-obvious until encountered
- Workarounds for tool limitations or environment quirks specific to this project
- Ordering constraints: "you must do X before Y or Z breaks"

---

## Step 2: Write Each Pattern File

For each extracted pattern, write a file to:

```
~/.claude/projects/$(pwd | tr '/' '-')/memory/learned-{slug}.md
```

Where `{slug}` is a short kebab-case name describing the pattern (e.g., `git-commit-via-node`,
`bun-test-isolation`, `k8s-secret-reload-order`).

This path matches Claude Code's own convention — the same directory as `MEMORY.md` for this
project (e.g., `/Users/dkay/code/cc-forge` → `~/.claude/projects/-Users-dkay-code-cc-forge/memory/`).

### Required Fields (all eight must be present in every learned file):

```markdown
# Learned: {descriptive title}

Extracted: {YYYY-MM-DD}
Confidence: {high | medium | low}

## Context
{1-3 sentences: what project/situation, what were you trying to accomplish?}

## Pattern
{The core insight in 1-3 sentences. What is the pattern? What does it enable?}

## When to Apply
{Bullet list: specific conditions under which this pattern applies}

## Steps
{Numbered steps to apply the pattern. Specific enough to follow without guessing.}

## Why This Works
{Brief explanation of the underlying mechanism. Why does this work, not just that it works.}

## Source
{Session date + task ID or description that produced this pattern, e.g., "2026-02-26 — T010 (token discipline plan)"}
```

### Security Guard (mandatory — enforce on every extraction):

Before writing any learned file, verify it contains NONE of the following:
- Actual credential values, tokens, passwords, or API keys
- Connection strings with embedded credentials
- Environment variable values (the variable NAME is fine; the VALUE is not)
- File contents that themselves contain sensitive data
- IP addresses or hostnames of internal/production systems

If a pattern cannot be described without revealing sensitive data, **do not extract it.**
Write a note to the operator instead: "Pattern identified but not extracted — would require
embedding sensitive configuration. Document manually with values redacted."

---

## Step 3: MEMORY.md Housekeeping

After writing learned files, update `MEMORY.md` in the same directory:

```bash
# Count current MEMORY.md lines
wc -l ~/.claude/projects/$(pwd | tr '/' '-')/memory/MEMORY.md
```

**If line count exceeds 180:**

1. Archive the current content to:
   ```
   ~/.claude/projects/$(pwd | tr '/' '-')/memory/archive-{YYYY-MM-DD}.md
   ```
2. Replace the archived sections in `MEMORY.md` with a single-line reference per archived topic:
   ```
   ## {Topic Name}
   Archived to archive-{YYYY-MM-DD}.md — {one sentence summary of what was archived}
   ```
   Keep the most recently updated sections in `MEMORY.md` directly; archive older ones.

**For each pattern just extracted:**

Add a single-line summary reference to the relevant section of `MEMORY.md`:
```markdown
- Learned: {slug} — {one sentence} → `memory/learned-{slug}.md`
```

Do NOT copy the full pattern content into `MEMORY.md`. The reference is enough.
Full content lives in `learned-{slug}.md`. Keep `MEMORY.md` scannable.

---

## Step 4: Confirm

Report to the operator:

```
Extraction complete.

Patterns extracted: {N}
  - learned-{slug1}.md — {one-line description}
  - learned-{slug2}.md — {one-line description}

Patterns skipped (already documented or too simple): {N}

MEMORY.md: {N lines — under threshold / archived to archive-{date}.md}

To apply these patterns in a future session, Claude Code will surface them
automatically when this project is opened (they live in the project memory directory).
```

If nothing was extracted (all candidates were too simple or already documented), say so
directly: "No new patterns extracted — all discoveries from this session were either
trivial or already documented."

---

## Rules

- This command is read-only on the project codebase. It writes only to
  `~/.claude/projects/{project-path}/memory/`.
- Never write credentials or sensitive values to any learned file.
- Patterns describe HOW solutions work, not WHAT values were used.
- Confidence levels: `high` = verified working in production or multiple contexts;
  `medium` = worked once, likely generalizes; `low` = worked in this specific case,
  may not generalize.
- If uncertain whether something is worth extracting, err toward skipping. A sparse,
  high-quality memory is better than a bloated, noisy one.
