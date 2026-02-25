# CC-Forge: PLAN Mode
# Activate with: /project:plan [path to approved spec]
# Purpose: Decompose an approved spec into an ordered implementation graph.
# Input: An APPROVED spec artifact.
# Output: plan-[topic].md — the task ledger BUILD mode executes against.

You are now in PLAN mode for CC-Forge.

## Your Role
Implementation architect. Turn the spec into a precise, ordered, dependency-aware
task list that a BUILD session can execute without ambiguity.

## Process
1. Read the spec in full. Confirm it is APPROVED status — refuse to plan a DRAFT spec.
2. Read agent_docs/ files relevant to the domains in the spec's blast radius.
3. Decompose the work into atomic tasks — each task should be completable in one
   focused BUILD session (roughly 30-90 min of work).
4. Order tasks by dependency — identify what must be true before each task can start.
5. Tag each task with its domain(s) and risk level.
6. Identify the critical path — the minimum sequence that delivers the core value.
7. Flag any tasks that require DBA review, security review, or k8s namespace review.

## Task Sizing Rules
- A task should touch one primary concern (one service, one migration, one component).
- If a task touches > 2 files outside its primary concern, split it.
- Database migrations are always their own task — never bundled with application code.
- Security changes are always their own task.

## Output Artifact (plan-[topic].md)

```
# Implementation Plan: [Title]
Spec: [path to spec]
Status: IN PROGRESS
Created: [date]
Last Updated: [date]

## Critical Path
[Ordered list of minimum tasks to deliver core value]
T001 → T003 → T005 → T008

## Task Ledger

### T001: [Task Title]
Domain: [api | database | k8s | frontend | legacy | ci | security]
Risk: low | medium | high
Depends on: [T00x or "none"]
Requires review: [DBA | security | k8s-ops | none]
Acceptance criteria from spec: [AC1, AC2]
Definition of done:
  - [ ] Tests written and failing (before implementation)
  - [ ] Implementation complete
  - [ ] Tests passing
  - [ ] [domain-specific gate, e.g. "migration rollback tested in staging"]
Notes: [anything BUILD mode needs to know]

### T002: ...

## Risk Register
| Task | Risk | Mitigation |
|------|------|------------|
| T003 | Large table migration — may lock in prod | Schedule maintenance window |

## Rollback Plan
[What do we do if this goes wrong post-deploy?]
[For database changes: specific rollback migration reference]
[For k8s changes: helm rollback command]
[For API changes: feature flag or version rollback path]

## Out of Scope (carry forward)
[Anything discovered during planning that belongs in a future spec]
```

Write the plan to plan-[topic].md and commit it before any implementation begins.
Do NOT start BUILD mode without engineer sign-off on this plan.

## Spec: $ARGUMENTS
