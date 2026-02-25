---
last_verified: YYYY-MM-DD
last_verified_by: [session-id or engineer-name]
drift_check: compare against src/legacy/ file structure — verify include chain map is current
---

# Legacy PHP Guide

> Template — populate during `/discuss` session.
> This document is critical for safe legacy work. Read it before touching any PHP.
> Replace all `[FILL IN]` sections. Delete this instruction line when done.

## The Cardinal Rule

**Do no harm to working production code.**

Every change to legacy PHP follows this protocol:
1. Write characterization tests FIRST (capture current behavior)
2. Make the change
3. Verify tests still pass
4. Document what you changed and why

## Entry Points

[FILL IN: How does execution start? What are the main entry files?]

```
[FILL IN: Map the include chain. Example:]
public/index.php
  └── includes/bootstrap.php
        ├── config/db.php         (database connection)
        ├── includes/auth.php     (session / auth functions)
        └── includes/functions.php (global utility functions)
```

**IMPORTANT:** Trace the full include chain before deleting or modifying any file.
Never assume a file is unused because it's not directly required by name.

## Database Access Pattern

[FILL IN: How does this PHP code connect to the database?]
- **Connection:** [mysqli / PDO / custom wrapper]
- **Location:** `[config/db.php or similar]`
- **Query pattern:** [parameterized? direct concatenation? — document both what IS and what SHOULD be]

## Authentication / Sessions

[FILL IN: How does auth work in the legacy code?]
- **Session start:** [where `session_start()` is called]
- **Auth check pattern:** [how pages verify the user is logged in]
- **User object:** [what's in `$_SESSION` — fields, structure]

## Global Functions and Variables

[FILL IN: Document the most-used global functions and what they do]

| Function | File | Purpose |
|----------|------|---------|
| `[function_name]()` | `[file]` | [what it does] |

## Known Hazards

[FILL IN: Things that are dangerous to touch, known bugs, implicit dependencies]

- **Don't touch `[file]`** without reading [explanation]
- **`[function]()` has a side effect** — [what the side effect is]
- **This file is included by 17 other files** — changing it breaks everything

## Refactor Protocol

When refactoring legacy PHP:
1. `grep -r "function_name\|ClassName" .` — find ALL usages
2. Write characterization tests for current behavior
3. Make the smallest possible change
4. Run `php -l [file]` before committing
5. Test in staging — legacy code has surprises

## Testing Legacy PHP

[FILL IN: What testing infrastructure exists, if any?]

For code with no tests, write regression tests before any change:
```php
<?php
// tests/regression/test_[feature].php
require_once __DIR__ . '/../../includes/bootstrap.php';

// Capture current behavior — don't judge it, just document it
$result = [function_to_test]([known_input]);
assert($result === [known_output], 'Regression: [describe what broke]');

echo "Regression tests passed\n";
```
