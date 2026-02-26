---
description: CC-Forge BUILD — execute a single task from an approved plan. TDD-first.
context: fork
allowed-tools: Bash, Read, Write, Edit, Glob, Grep, Task
---

# CC-Forge: BUILD — Single Task Execution
# Invoked headless by ~/.claude/loops/build.sh via: claude -p "..." --json-schema build-signal-schema.json
# Also usable interactively: /build plan-auth.md T003
#
# Purpose: Execute ONE task from an approved plan. TDD-first. Emit the JSON signal.
# Input: Plan path + task ID
# Output: JSON object conforming to build-signal-schema.json

You are executing one task from an approved CC-Forge implementation plan.
Headless mode (from build.sh): plan path and task ID are in the prompt above.
Interactive mode: they are in $ARGUMENTS below.

---

## Pre-Build Checklist (run BEFORE touching any code)

- [ ] Read `.claude/forge/registry/project-graph.json` — identify all entities this task will
      **create, modify, or delete**. State the blast radius explicitly before starting.
- [ ] Confirm this task is unblocked: all tasks in its `Depends on:` list are marked complete.
- [ ] Read the relevant `agent_docs/` files for this task's domain (api-patterns, database-schema, k8s-layout, etc.)
- [ ] Confirm you are on a correctly named branch: `feat|fix|chore|refactor|sec/[slug]`
- [ ] Read the task's `Acceptance criteria` and `Definition of done` from the plan.

---

## TDD Discipline (non-negotiable — no exceptions for "simple" tasks)

1. **Write the failing test** that proves the acceptance criterion is satisfied when done.
2. **Run it. Confirm it fails** for the right reason (not setup error, not wrong test).
3. **Commit the failing test:** `test([scope]): [AC description] - RED`
4. **Implement** the minimum code to make the test pass. No more. No gold-plating.
5. **Run it. Confirm it passes.**
6. **Refactor** if needed — tests must stay green throughout.
7. **Commit the implementation:** `[type]([scope]): [what and why — not how]`
8. Repeat for each acceptance criterion in the task.

---

## Domain-Specific Gates

### API Changes
- Auth middleware present on every new route — verify before committing.
- `docs/api/openapi.yaml` updated alongside implementation (not after, alongside).
- Error responses use the shared ApiError class — never raw `res.json()` for errors.
- Correlation ID propagated to all downstream service calls.
- All untrusted input validated at the route boundary.

### Database Changes
- Migration naming: `V{n}__{PascalCaseDescription}.sql`
- Rollback script **required**: `db/migrations/undo/U{n}__{PascalCaseDescription}.sql`
- Destructive operations (DROP TABLE, DROP COLUMN, TRUNCATE, DELETE without WHERE) →
  **STOP.** Requires `[break_glass] destructive_migrations = true` in project.toml with justification.
- New queries on tables with > 10,000 rows → include `EXPLAIN` output in commit message or PR description.
- All SQL parameterized — zero string concatenation, zero f-string SQL, zero sprintf SQL. Ever.
- Test migration against staging DB before marking task done.

### k8s Changes
- Resource requests AND limits on every container — no unbounded containers.
- Liveness and readiness probes present before any deployment.
- Run `helm diff` and review the output before `helm upgrade`.
- RBAC changes: state blast radius explicitly in commit message.
- `microk8s kubectl`, never bare `kubectl`.

### Frontend Changes (Nuxt, TypeScript)
- TypeScript strict mode — no `any` without an explanatory comment (`// any: reason`).
- No business logic in components — extract to composables or services.
- Every interactive element has an `aria-label` or explicit `role`.
- New pages: run Lighthouse CI before marking done.

### Legacy PHP Changes
- Characterization tests written BEFORE any refactor — capture and commit current behavior first.
- No dynamic includes: `include($variable)` is forbidden.
- No `eval()`. No exceptions.
- All user input validated. All output HTML-escaped.
- Run `php -l [file]` before every commit.
- Flag in commit message if any modified function exceeds 50 lines.

---

## Security Gates (run on every task — not just security tasks)

```bash
bun run typecheck      # No type errors committed
bun run lint           # No lint violations committed
git secrets --scan     # No credentials staged
```

---

## Task Completion

When implementation is done and all tests pass:

1. **Update the plan:** mark this task complete with a timestamp.
2. **Update `project-graph.json`:** if any entities or relationships were created, modified, or deleted.
3. **Update relevant `agent_docs/`:** if anything undocumented was discovered during implementation.
4. **Final commit:** `[type]([scope]): [what and why, not how]`

---

## Emit JSON Signal

Output ONLY valid JSON. Nothing before it. Nothing after it. No markdown fences.

Required fields:
- `status`: `"next"` (more tasks remain in plan) | `"complete"` (this was the last task) | `"blocked"` (human input required) | `"failed"` (tests did not pass)
- `task_id`: ID of the task just attempted (e.g., `"T003"`)
- `completed_tasks`: all task IDs completed so far in this build run
- `next_task`: ID of the next task, or `null` if complete/blocked
- `blockers`: array of `{task_id, reason}` — empty array if none
- `tests_passed`: `true` or `false` — if false, build.sh will halt
- `commit_hash`: short git hash of implementation commit, or `null` if uncommitted
- `summary`: one sentence (10–300 chars) describing what this task accomplished

Example output:
```json
{
  "status": "next",
  "task_id": "T003",
  "completed_tasks": ["T001", "T002", "T003"],
  "next_task": "T004",
  "blockers": [],
  "tests_passed": true,
  "commit_hash": "a3f9c12",
  "summary": "Implemented JWT refresh token rotation with 7-day expiry and secure httpOnly cookie storage."
}
```

## Plan/Task: $ARGUMENTS
