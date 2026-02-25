# CC-Forge: IMPROVE — Single Iteration
# Invoked headless by ~/.claude/loops/forge-loop.sh via: claude -p "..." --json-schema improve-signal-schema.json
# NOT a loop controller. Execute ONE pass. Emit the JSON signal. Stop.
#
# The loop controller reads .structured_output and decides whether to iterate.
# Claude does NOT control loop continuation.

You are executing one iteration of the CC-Forge Forge Loop.
Do NOT attempt to loop internally. Execute one improvement pass. Emit the JSON signal. Done.

---

## Step 1: MEASURE (establish or update baseline)

Run the measurement suite appropriate to this project. Record all numbers.

```bash
# TypeScript / JavaScript / Nuxt projects
bun run typecheck 2>&1 | tail -5
bun run lint --reporter=json 2>/dev/null | jq '.diagnostics | length' 2>/dev/null \
  || bunx biome check --reporter=json . 2>/dev/null | jq '.diagnostics | length' 2>/dev/null \
  || echo "0"
bun run test:coverage --reporter=json 2>/dev/null | jq '.total.lines.pct / 100' 2>/dev/null || echo "0"
npx ts-complexity src/ --threshold 10 2>/dev/null | wc -l | tr -d ' ' || echo "0"

# Python projects
python3 -m mypy . --output=json 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(len(d.get('errors',[])))" 2>/dev/null || echo "0"
python3 -m ruff check --output-format=json . 2>/dev/null | jq 'length' 2>/dev/null || echo "0"

# PHP projects
find . -name "*.php" -not -path "*/vendor/*" -exec php -l {} \; 2>&1 | grep -c "^Errors\|^Parse error" || echo "0"
```

Record all baseline values before making any changes. These populate the `metrics` field.

---

## Step 2: READ SCOPE REGISTRY

Read `.claude/forge/registry/project-graph.json`.

Identify all entities whose `path` falls within the scope provided in the prompt.
**Only improve entities within the declared scope.** Do not touch entities outside it.
If the registry is empty, scope to all files within the declared path.

---

## Step 3: IDENTIFY (rank opportunities, pick ONE top item)

Score each identified opportunity on three axes:

```
Score = Impact (1–5) + Effort_Inverse (5=trivial, 1=large) + Risk_Inverse (5=safe, 1=risky)
Minimum score to act: 6
```

Examples:
- Remove dead code: Impact=3, Effort_Inv=5, Risk_Inv=5 = **Score 13** ✅ Act on this
- Major refactor of auth module: Impact=4, Effort_Inv=1, Risk_Inv=2 = **Score 7** ✅ Act if time
- Change public API shape: Impact=3, Effort_Inv=2, Risk_Inv=1 = **Score 6** — only if absolutely clear

**Pick ONE item.** The highest-scoring item becomes `next_focus` in the output.

Improvement items:
- MUST NOT change external behavior (refactors, dead code removal, test addition only)
- MUST NOT require DB migrations (those belong in BUILD mode)
- MUST stay within the declared scope
- MUST be completable in this single iteration

---

## Step 4: IMPROVE (execute the top item)

One improvement. No more.

Mini TDD cycle (even for refactors):
1. If no test covers the code being changed, write one that characterizes current behavior
2. Make the change
3. Verify the test still passes (and any new tests pass)
4. Commit: `improve([scope]): [what changed and why — not how]`

If the improvement reveals a bug or a required-but-risky change:
- **STOP.** Do NOT fix the bug inline.
- Add it to `blockers` with a clear description.
- Set status to `"blocked"` if human input is needed, or continue with a lower-scoring item.

---

## Step 5: VERIFY

Re-run the full measurement suite from Step 1. Compare to baseline.

Calculate aggregate delta:
```
delta = (improvements_count / total_opportunities_identified) × (metric_score_improvement / max_possible)
```

Simplified: a rough 0.0–1.0 estimate of how much was improved vs. how much was possible.
- All targeted metrics improved → delta 0.15–0.30 typical
- No measurable improvement → delta 0.0
- Major metric improvement → delta 0.5+

**Regression check:** Every non-targeted metric must not regress by > 2%.
If any metric regressed, revert the change and add the item to `skipped`.

---

## Step 6: EMIT JSON SIGNAL

Output ONLY valid JSON. Nothing before it. Nothing after it. No markdown fences.

Required fields:
- `status`: `"loop"` (delta > threshold, more work possible) | `"complete"` (queue exhausted or delta near zero) | `"blocked"` (human input needed) | `"error"` (something broke)
- `iteration`: the iteration number from the prompt
- `delta`: 0.0 to 1.0 improvement estimate
- `metrics`: current measurements after this iteration
- `completed`: array of descriptive slugs for items completed this iteration
- `skipped`: array of slugs for items skipped (if any)
- `blockers`: array of `{id, reason}` objects (empty array if none)
- `next_focus`: slug of top opportunity for next iteration (empty string if complete)
- `summary`: one sentence (10–300 chars) describing what happened

Example output:
```json
{
  "status": "loop",
  "iteration": 2,
  "delta": 0.18,
  "metrics": {
    "typecheck_errors": 0,
    "lint_findings": 4,
    "test_coverage": 0.83,
    "complexity_score": 38
  },
  "completed": ["remove-dead-feature-flag-experiment-v2", "add-test-coverage-auth-refresh"],
  "skipped": [],
  "blockers": [],
  "next_focus": "reduce-cyclomatic-complexity-payment-processor",
  "summary": "Removed dead feature flag and added 3 missing auth refresh tests, improving coverage from 0.78 to 0.83."
}
```

## Scope: $ARGUMENTS
