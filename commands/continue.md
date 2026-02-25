---
description: Resume from a CC-Forge handoff document. Loads state, presents a situation report, confirms before touching anything.
allowed-tools: Read, Write, Bash, Glob
---

# CC-Forge Continue — Resume Session

Your job: orient from the handoff, verify current state, present a SITREP,
and get operator confirmation before doing any work.

**Read-only until confirmed.** No file edits, no commands beyond git/state reads.

---

## Step 1: Find the Handoff

Check for a registered pending handoff:
```bash
cat ~/.claude/pending-resume 2>/dev/null
```

**If found:**
- Read the path (trim whitespace)
- Read the handoff document at that path
- Note the timestamp embedded in the filename (staleness indicator)
- Clear the marker after reading: `rm -f ~/.claude/pending-resume`

**If not found:**
- Check `.forge/handoffs/` for the most recent handoff:
  ```bash
  ls -t .forge/handoffs/*.md 2>/dev/null | head -1
  ```
- If found, read it. Note it wasn't registered (may be from a previous session).
- If nothing found: tell the operator:
  "No handoff found. Run `/forge--handoff` to create one, or describe what
  you were working on and I'll orient from scratch."

**Also check Golem handoffs** (coexisting system):
```bash
ls -t .golem/handoffs/*.md 2>/dev/null | head -1
~/.claude/handoffs/handoff-*.md  (fallback location)
```
If a Golem handoff is newer than any Forge handoff, note both and ask which to use.

---

## Step 2: Load Current State

Read these to verify the handoff is still accurate:

```bash
git branch --show-current
git status --short
```

Also read:
- `.forge/state.json` — current phase (compare with handoff)
- `.forge/security.json` — security score (flag if worse than handoff)

---

## Step 3: Present SITREP

Present this summary BEFORE asking any questions or doing any work:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  RESUMING SESSION
  Handoff: {timestamp from filename} ({N hours/minutes ago})
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  Phase:    {from state.json}
  Branch:   {current branch}
  Git:      {clean / N changed files (list them if dirty)}
  Security: {score}/100{  ⚠️  SCORE DROPPED since handoff — run /forge--sec first}

  ┌─ CURRENT FOCUS ────────────────────────────────────
  │ {from handoff}
  └────────────────────────────────────────────────────

  ┌─ WHAT'S NEXT ──────────────────────────────────────
  │ {ordered list from handoff}
  └────────────────────────────────────────────────────

  ┌─ GOTCHAS ──────────────────────────────────────────
  │ {from handoff}
  └────────────────────────────────────────────────────

  Plan: {N}/{M} tasks complete ({%}) — {plan-filename.md}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

**State drift warnings** — note these if they exist:
- Working tree is dirtier than handoff expected (uncommitted changes exist from before)
- Branch differs from what handoff expected
- Security score dropped
- Handoff is more than 24 hours old

---

## Step 4: Handle Optional Focus Argument

If `$ARGUMENTS` is provided (e.g., `/forge--continue "finish the auth rate limiter"`):
- Display it as "Narrowed Focus: {$ARGUMENTS}"
- Incorporate it into the next steps — override handoff's "What's Next" order if relevant

---

## Step 5: Confirm Before Proceeding

Ask exactly this:

> Does this match your understanding? Should I proceed with "What's Next", or
> would you like to redirect?

Wait for operator response. Do NOT modify any files or start work until confirmed.

---

## Step 6: Resume

After confirmation:
- Start from "What's Next" — pick up exactly where the handoff left off
- Do NOT re-plan, re-ask, or re-explain decisions already captured in the handoff
- Do NOT add ceremony — after confirmation, just work

---

## Rules

- Show the handoff timestamp so the operator can judge staleness
- A handoff from today is fresh; one from last week needs verification
- If the handoff mentions a plan file, confirm it still exists before referencing it
- If both a Forge and Golem handoff exist, ask which to use — don't guess
- After confirmation, trust the handoff. Don't second-guess decisions that are documented
