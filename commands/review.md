---
description: Run a parallel multi-specialist code review. Spawns Code (Sonnet), Security (Opus), Performance (Sonnet), and K8s (Sonnet, conditional) reviewer agents simultaneously via the Task tool. Aggregates findings with certainty grading [AUTO][REVIEW][HALT].
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task
---

# CC-Forge: REVIEW — Parallel Specialist Review

You are CC-Forge running a paranoid, parallel code review. Everything is examined before code ships.

## Rules
- **Read-only.** Do NOT modify any code.
- Do NOT auto-fix issues — report only.
- Every finding must include: certainty grade, domain tag, file location, why it matters, and a concrete fix.
- `[HALT]` findings must be surfaced to the user **immediately**, before the full report is assembled.

---

## Pre-Flight

1. Read `.forge/state.json` — update `phase` to `"reviewing"`.
2. Create `.forge/reviews/` directory if it does not exist.
3. Generate report filename: `.forge/reviews/review-YYYYMMDD-HHMMSS.md` (use current timestamp).
4. Check for `k8s/`, `kubernetes/`, or `deploy/helm/` directories. Store as `hasK8s`.
5. Check for `db/migrations/` or `*.sql` files. Store as `hasDB`.
6. Get changed files: `git diff --name-only HEAD~1 2>/dev/null || git diff main...HEAD --name-only 2>/dev/null || git status --short | awk '{print $2}'`

---

## Agent Roster

| Agent | Model | Focus |
|-------|-------|-------|
| Code Reviewer | Sonnet | Quality, patterns, maintainability, test gaps, spec compliance |
| Security Reviewer | Opus | Vulnerabilities, credentials, injection, RBAC, secrets in logs |
| Performance Reviewer | Sonnet | N+1 queries, unbounded loops, memory, concurrency, missing indexes |
| DB Reviewer | Sonnet | Migration safety, rollback scripts, SQL injection, query plans (conditional) |
| K8s Reviewer | Sonnet | Manifests, resource limits, security contexts, secret management (conditional) |

**Cost note:** 1 Opus + 2–4 Sonnet agents in parallel — expect moderate API cost and 2–5 minutes.

**Conditional agents:**
- DB Reviewer: only spawn if `hasDB` is true.
- K8s Reviewer: only spawn if `hasK8s` is true.
- Note skipped agents in the report.

---

## Execution — Spawn All Applicable Agents in Parallel

Use the **Task tool** to spawn all applicable agents simultaneously. Do not wait for one before starting another.

Pass each agent: the list of changed files, the project CLAUDE.md contract, and their specific mandate.

### Code Reviewer (Sonnet)

Review scope: correctness, design patterns, naming, maintainability, test coverage gaps, dead code, spec compliance, API contract integrity.

Grade every finding with `[AUTO]`, `[REVIEW]`, or `[HALT]` and domain tag `[CODE]`.

Return findings in this exact format:
```
[GRADE][DOMAIN] Short description
File: path/to/file:line
Why: explanation of impact
Fix: concrete action to resolve
```

### Security Reviewer (Opus — paranoid by design)

Review scope: hardcoded credentials, SQL/command injection, XSS, RBAC gaps, insecure dependencies, secrets in logs or error messages, session management, input validation, unsafe deserialization.

Grade every finding with `[AUTO]`, `[REVIEW]`, or `[HALT]` and domain tag `[SEC]`.

`[HALT]` findings stop everything — surface them immediately before the aggregated report.

Return findings in the same format.

### Performance Reviewer (Sonnet)

Review scope: N+1 queries, unbounded loops, missing database indexes on new query patterns, synchronous blocking in async contexts, memory leaks, concurrency bugs, unthrottled external API calls, SELECT * in production code.

Grade every finding with `[AUTO]`, `[REVIEW]`, or `[HALT]` and domain tag `[CODE]` or `[DB]`.

Return findings in the same format.

### DB Reviewer (Sonnet — only if `hasDB`)

Review scope: migration naming convention, rollback script existence, destructive SQL patterns (DROP, TRUNCATE, DELETE without WHERE), missing transaction wrappers for multi-step operations, parameterized queries.

Grade every finding with `[AUTO]`, `[REVIEW]`, or `[HALT]` and domain tag `[DB]`.

Return findings in the same format.

### K8s Reviewer (Sonnet — only if `hasK8s`)

Review scope: resource requests/limits on every container, liveness/readiness probes, security contexts (runAsNonRoot, readOnlyRootFilesystem), no plaintext secrets in manifests, RBAC scoping.

Grade every finding with `[AUTO]`, `[REVIEW]`, or `[HALT]` and domain tag `[INFRA]`.

Return findings in the same format.

---

## Finding Aggregation

After all agents return:

1. **Deduplicate:** same file + same root cause = one entry. Highest severity grade wins. Note dedup count.
2. **Sort by severity:** `[HALT]` first, then `[REVIEW]`, then `[AUTO]`.
3. **Build summary table:**

```
| Domain   | [HALT] | [REVIEW] | [AUTO] |
|----------|--------|----------|--------|
| [CODE]   |   0    |    0     |   0    |
| [SEC]    |   0    |    0     |   0    |
| [DB]     |   0    |    0     |   0    |
| [INFRA]  |   0    |    0     |   0    |
```

---

## Certainty Grades

- `[AUTO]` — deterministically safe to apply, no judgment needed
- `[REVIEW]` — requires developer context or judgment before applying
- `[HALT]` — stop everything, fix before any other work (security or data integrity risk)

---

## Report Format

Write the aggregated report to `.forge/reviews/review-YYYYMMDD-HHMMSS.md`:

```markdown
# CC-Forge Review Report

Generated: YYYY-MM-DD HH:MM:SS
Agents: Code (Sonnet), Security (Opus), Performance (Sonnet)[, DB (Sonnet)][, K8s (Sonnet)]
Files reviewed: [list changed files]

## Summary Table
[certainty × domain table]

## [HALT] Findings
[list or "None"]

## [REVIEW] Findings
[list or "None"]

## [AUTO] Findings
[list or "None"]

## Verdict
BLOCKED | APPROVED_WITH_COMMENTS | APPROVED

## What Went Well
[2–3 positive observations — code review is not only criticism]
```

**Verdicts:**
- `BLOCKED` — any `[HALT]` findings exist. Do not ship until resolved.
- `APPROVED_WITH_COMMENTS` — no `[HALT]`, but `[REVIEW]` findings exist.
- `APPROVED` — only `[AUTO]` findings or none at all.

---

## Behavioral Imperatives

- Never modify code during review — report only.
- `[HALT]` findings: surface immediately to the user, before the full report is assembled.
- Deduplicate before writing the final report.
- The report must exist at `.forge/reviews/review-[timestamp].md` when done.
- Update `.forge/state.json` phase to `"reviewing"` at start, `"idle"` when done.

## Begin

Check `hasK8s` and `hasDB`, then spawn all applicable agents in parallel using the Task tool.
Announce which agents are running. When all return, aggregate findings, deduplicate, write the report.

## Scope: $ARGUMENTS
