# CC-Forge: SIMPLIFY Mode
# Activate with: /project:simplify [scope: "full" | "domain:[name]" | "file:[path]"]
# Purpose: Structural complexity reduction. Different from IMPROVE — goal is less code,
#          not better code. Fewer abstractions, smaller surface area, lower cognitive load.
# Trigger: Manual only. Never run automatically. Requires deliberate decision.
# Output: Simpler codebase with identical external behavior, verified by tests.

You are now in SIMPLIFY mode for CC-Forge.

## The Simplify Philosophy
The best code is code that doesn't exist. The second best is code that is so clear
it needs no comment. Simplification is not about style — it's about structural mass.
A simplified system has less to maintain, less to understand, less to break.

This mode asks four questions in sequence and stops when none yield actionable items:

```
1. DELETE  → Can this be removed entirely? (dead code, unused deps, orphaned resources)
2. MERGE   → Can two things become one? (duplicate logic, parallel implementations)
3. REPLACE → Is there a simpler solution that exists now? (libraries, platform features)
4. CLARIFY → Can this be made self-documenting? (rename, restructure, extract)
```

## Pre-Simplify Gate
Tests MUST be passing before simplify begins. Run:
```bash
bun run test
bun run typecheck
```
If tests fail, STOP. Fix them first. Simplify only runs on green.

## Process

### Step 1: Survey the Scope
Read agent_docs/architecture.md and relevant domain docs.
Build a list of candidates for each of the four questions.
Do not simplify anything not in the defined scope.

### Step 2: DELETE Pass
Find and verify:
- Dead code (unused exports, unreachable branches, commented-out code > 30 days old)
- Unused dependencies (package.json / requirements.txt / composer.json)
- Orphaned k8s resources (deployments/configmaps with no active consumers)
- Deprecated API endpoints with zero traffic (verify with logs before removing)
- Stale feature flags (fully rolled out or permanently disabled)
- Outdated migrations that have been applied everywhere (archivable, not deletable)

For each candidate: verify it's safe to remove, remove it, run tests, commit.
Commit format: `simplify([scope]): delete [what] — [why it's dead]`

### Step 3: MERGE Pass
Find and verify:
- Duplicate business logic across services or files (> 80% similar implementation)
- Parallel implementations of the same feature (A/B that's been decided)
- Utility functions that do the same thing under different names
- Config that's duplicated across environments when it could be derived

For each candidate: consolidate, run tests, commit.
Commit format: `simplify([scope]): merge [what] — [why they're the same]`

### Step 4: REPLACE Pass
Find and verify:
- Custom implementations that a well-maintained library now handles better
- Complex workarounds for platform limitations that have since been fixed
- Hand-rolled solutions for things the framework provides natively (Nuxt, Express)
- SQL stored procedures that a simpler ORM pattern would handle

For each candidate: replace, run tests, verify behavior is identical, commit.
Commit format: `simplify([scope]): replace [custom thing] with [simpler thing]`

### Step 5: CLARIFY Pass
Find and verify:
- Functions that require a comment to understand → can the code be restructured to be
  self-documenting instead? (rename params, extract intermediate variables, split function)
- Files that mix multiple concerns → extract
- Abstractions that add indirection without adding value → inline them
- Config values that are magic numbers → make them named constants with context

For each candidate: clarify, run tests, commit.
Commit format: `simplify([scope]): clarify [what] — [what was unclear]`

## Simplify Gate
Each simplification requires:
- [ ] Tests still pass (run after each change — do not batch)
- [ ] External behavior unchanged (API contracts, data formats, UI output identical)
- [ ] Complexity delta meaningful: only act if cognitive load is measurably reduced
      (target: > 10% reduction in file length OR removal of one abstraction layer)
- [ ] No performance regression (check if the change touches a hot path)

## What Simplify Is NOT
- Not a style pass. Run the linter for that.
- Not a performance optimization. That's IMPROVE.
- Not an architectural redesign. That's a new SPEC.
- Not a refactor that changes behavior. Tests must prove behavior is identical.

## Session Archive (.claude/forge/history/simplify-[date].md)
```
# Simplify Session: [date]
Scope: [full | domain:X | file:Y]

## Changes Made
| Pass    | Description | Files Changed | Lines Delta | Commit |
|---------|-------------|---------------|-------------|--------|
| DELETE  | ...         | ...           | -120        | abc123 |
| MERGE   | ...         | ...           | -45         | def456 |

## Net Result
Lines removed: [n]
Files removed: [n]
Dependencies removed: [n]
Abstractions collapsed: [n]

## Carry Forward
[Candidates identified but not acted on — explain why]
```

## Scope: $ARGUMENTS
