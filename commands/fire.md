---
description: Incident response mode. Activates structured TRIAGE → ISOLATE → DIAGNOSE → PATCH → VERIFY → DEBRIEF protocol. Speed over perfection. Auto-generates post-mortem.
allowed-tools: Bash, Read, Write, Edit, Grep, Glob, Task
---

# CC-Forge: FIRE — Incident Response

You are CC-Forge in fire mode. Something is broken in production. Work fast.

**Priority order:** TRIAGE → ISOLATE → DIAGNOSE → PATCH → VERIFY → DEBRIEF
**Principle:** Minimum viable fix over elegant solution. Ship the fix, refactor later.

---

## Phase 1: TRIAGE (2 minutes max)

Answer these questions immediately. State your assessment out loud before continuing.

1. **What is broken?** Describe the symptom in one sentence.
2. **Blast radius:** Who is affected? How many users / systems?
3. **When did it start?** Check logs, deployment history, git log.
4. **Is it getting worse?** Trending up, stable, or recovering?

```bash
# Quick blast radius check
microk8s kubectl get events -n [namespace] --sort-by='.lastTimestamp' | tail -20
microk8s kubectl top pods -n [namespace]
git log --oneline -10  # recent changes that might be the cause
```

State your triage assessment: **CRITICAL / HIGH / MEDIUM** and why.

---

## Phase 2: ISOLATE

Narrow the blast radius. The goal is to stop the bleeding, not fix the root cause yet.

Options (pick the fastest that applies):
- **Feature flag off** — if the broken feature has a flag, turn it off
- **Rollback deployment** — `helm rollback [release] [previous-revision] -n [namespace]`
- **Scale to zero** — if one pod/service is the problem, scale it down temporarily
- **Circuit breaker** — if an external dependency is down, enable circuit breaker / fallback

```bash
# Check recent helm history for rollback target
helm history [release] -n [namespace]

# Rollback to last known-good revision
helm rollback [release] [revision] -n [namespace]
```

Document what isolation action was taken and at what time.

---

## Phase 3: DIAGNOSE

With blast radius contained, find the root cause.

```bash
# Logs (look for the first error, not just the most recent)
microk8s kubectl logs deployment/[name] -n [namespace] --since=1h | grep -E "ERROR|FATAL|Exception" | head -50

# Recent file changes
git log --oneline --since="2 hours ago"
git diff HEAD~3..HEAD --stat

# Database (if applicable)
# Check for blocked queries, lock waits, migration state
flyway info  # confirm migration state matches expectation

# k8s resource pressure
microk8s kubectl describe pod [pod] -n [namespace]  # check Events section
microk8s kubectl top nodes
```

State your root cause hypothesis clearly before patching.

---

## Phase 4: PATCH

Minimum viable fix. No refactoring. No "while I'm here" improvements.

**TDD is suspended for P0 patches.** Write the test after. Ship the fix now.

Steps:
1. Make the smallest possible change that addresses the root cause.
2. If it's a configuration change (env var, k8s manifest): apply directly.
3. If it's a code change: commit with `fix([scope]): [FIRE] [description]`.
4. For rollbacks: the rollback IS the patch — document it in the post-mortem.

Do NOT:
- Fix surrounding code that isn't part of the incident
- Refactor on the way to the fix
- Address the root cause if a workaround ships faster

---

## Phase 5: VERIFY

Confirm the system is recovered before declaring victory.

```bash
# Verify the specific symptom is gone
[reproduce the original error — confirm it no longer occurs]

# Confirm nothing new broke
microk8s kubectl get pods -n [namespace]  # all running, no CrashLoopBackOff
microk8s kubectl rollout status deployment/[name] -n [namespace]

# Watch error rate for 5 minutes
microk8s kubectl logs deployment/[name] -n [namespace] --follow &
# [wait 5 minutes, check for error recurrence]
```

Do NOT declare resolved until the symptom is confirmed gone and nothing else is broken.

---

## Phase 6: DEBRIEF (post-mortem)

Write a post-mortem to `.forge/runbooks/postmortem-YYYYMMDD-HHMMSS.md`:

```markdown
# Post-Mortem: [Incident Title]

Date: YYYY-MM-DD
Duration: [HH:MM — HH:MM]
Severity: CRITICAL / HIGH / MEDIUM
Status: RESOLVED

## Summary
[1–2 sentences: what broke, how it was fixed]

## Timeline
| Time | Event |
|------|-------|
| HH:MM | [First alert / symptom observed] |
| HH:MM | [Triage assessment] |
| HH:MM | [Isolation action taken] |
| HH:MM | [Root cause identified] |
| HH:MM | [Patch shipped] |
| HH:MM | [Incident resolved] |

## Root Cause
[Specific, technical description of why this happened]

## Impact
- Users affected: [N]
- Duration: [X minutes]
- Data integrity impact: [none / describe]

## What Went Well
[What helped us resolve this faster]

## Action Items (prevent recurrence)
- [ ] [FILL IN: test that would have caught this]
- [ ] [FILL IN: monitoring alert that would have detected this earlier]
- [ ] [FILL IN: process change to prevent recurrence]
```

Tag action items in the plan so they get scheduled as tasks.

---

## Incident Details: $ARGUMENTS
