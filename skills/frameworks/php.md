# Legacy PHP Development Skill
# ~/.claude/forge/skills/frameworks/php.md
# Load this skill before working with the legacy PHP codebase.

## Critical Rule: Characterization Tests Before Any Refactoring

Before modifying ANY legacy PHP code, capture its current behavior in tests.
This is non-negotiable. The codebase has accumulated behavior over years that
may be intentional even when it looks like a bug. You must verify before changing.

```bash
# PHP test runner (check agent_docs/testing-guide.md for actual path)
./vendor/bin/phpunit tests/Legacy/

# Run characterization test for specific file
./vendor/bin/phpunit tests/Legacy/CharacterizationTest.php --filter testPlayerLookup
```

## Stack Context

- No framework — manual routing via a front controller or direct file includes
- PHP 7.x/8.x — check `phpversion()` before assuming language features
- PDO for all database access — no `mysql_*`, no `mysqli_*` anywhere new
- Composer for dependencies — `composer dump-autoload` after class additions
- PSR-4 autoloading where it exists; `require_once` in older files

## Database Access — PDO Only

```php
<?php
// CORRECT: PDO with prepared statements
function getPlayerById(PDO $pdo, string $playerId): ?array
{
    $stmt = $pdo->prepare(
        'SELECT player_id, first_name, last_name, active FROM dbo.Players WHERE player_id = :id'
    );
    $stmt->execute([':id' => $playerId]);
    $row = $stmt->fetch(PDO::FETCH_ASSOC);
    return $row !== false ? $row : null;
}

// WRONG: string concatenation = SQL injection
$result = $pdo->query("SELECT * FROM Players WHERE id = '$playerId'"); // ❌ NEVER

// WRONG: legacy functions that should not exist in any new code
$result = mysql_query("SELECT * FROM Players WHERE id = $playerId");   // ❌ NEVER
```

### PDO Connection Setup

```php
<?php
function createPdoConnection(): PDO
{
    // Credentials from environment — never hardcoded
    $dsn = sprintf(
        'sqlsrv:Server=%s,%s;Database=%s;Encrypt=yes',
        getenv('MSSQL_HOST'),
        getenv('MSSQL_PORT') ?: '1433',
        getenv('MSSQL_DATABASE')
    );

    return new PDO(
        $dsn,
        getenv('MSSQL_USER'),
        getenv('MSSQL_PASSWORD'),
        [
            PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
            PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
            PDO::ATTR_EMULATE_PREPARES   => false, // Use real prepared statements
        ]
    );
}
```

## Security Patterns

```php
<?php
// Output escaping — ALWAYS use htmlspecialchars() before echoing user data
echo htmlspecialchars($playerName, ENT_QUOTES, 'UTF-8');

// Input from GET/POST — validate, don't trust
$playerId = filter_input(INPUT_GET, 'player_id', FILTER_VALIDATE_INT);
if ($playerId === false || $playerId === null) {
    http_response_code(400);
    exit('Invalid player ID');
}

// CSRF protection for state-changing forms
// (check if there's an existing CSRF helper — look before writing your own)
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (!hash_equals($_SESSION['csrf_token'], $_POST['csrf_token'] ?? '')) {
        http_response_code(403);
        exit('CSRF validation failed');
    }
}

// File uploads — validate type and size, never trust client extension
if ($_FILES['upload']['type'] !== 'image/jpeg') {
    // Use mime_content_type() on the actual file, not $_FILES['type']
    $actualType = mime_content_type($_FILES['upload']['tmp_name']);
}
```

## Known Landmines

These patterns exist in the codebase and must NOT be replicated:

### Global State
```php
// LANDMINE: global variables used for config/session state
global $db;   // fragile, breaks in nested calls
global $user; // race conditions in async contexts

// SAFE PATTERN: pass dependencies explicitly
function processPayment(PDO $db, Player $player, float $amount): void { ... }
```

### Mixed HTML and Logic
```php
<!-- LANDMINE: business logic inside templates -->
<?php if ($player['balance'] > 1000 && !$player['flagged']): ?>
  <!-- This logic belongs in a service class, not the template -->
<?php endif ?>

<!-- SAFE PATTERN: compute in controller, pass to template -->
<?php // controller -->
$canWithdraw = $playerService->canWithdraw($player);
// template just renders:
<?php if ($canWithdraw): ?>
```

### Unguarded `include`/`require` with user input
```php
// CRITICAL LANDMINE — path traversal vulnerability
include $_GET['page'] . '.php'; // ❌ NEVER — path traversal attack

// SAFE: whitelist approach
$allowed = ['dashboard', 'profile', 'history'];
$page = in_array($_GET['page'], $allowed) ? $_GET['page'] : 'dashboard';
include __DIR__ . '/pages/' . $page . '.php';
```

### Suppressed errors (`@` operator)
```php
// LANDMINE: silently swallows errors, impossible to debug
$result = @mysql_query($sql);

// SAFE: use try/catch
try {
    $stmt = $pdo->prepare($sql);
    $stmt->execute($params);
} catch (PDOException $e) {
    // log properly, don't suppress
    error_log('DB error: ' . $e->getMessage());
    throw $e;
}
```

## Characterization Test Pattern

Before refactoring a function you don't fully understand:

```php
<?php
// tests/Legacy/CharacterizationTest.php
use PHPUnit\Framework\TestCase;

class CharacterizationTest extends TestCase
{
    /**
     * Captures the current behavior of calculateBonus() before refactoring.
     * Written 2026-02-23. If this test fails after your change, you changed behavior.
     */
    public function testCalculateBonusExistingBehavior(): void
    {
        // Snapshot what the function CURRENTLY does — even if it looks wrong
        // Don't fix anything yet. Capture first, then decide if it's intentional.
        $this->assertSame(150, calculateBonus(1000, 'gold'));
        $this->assertSame(0, calculateBonus(0, 'gold'));
        $this->assertSame(50, calculateBonus(1000, 'silver'));
        // Edge case that looked suspicious but is real behavior:
        $this->assertSame(150, calculateBonus(-500, 'gold')); // negative input returns same as positive?
    }
}
```

Run characterization tests to establish a baseline, then:
1. Run tests → all pass (baseline captured)
2. Make your change
3. Run tests again → any failure = you changed behavior. Decide if intentional.

## Adding New Code to Legacy

When adding new code near legacy patterns:

- New functions: PSR-4 class files with proper namespacing, not procedural files
- New database queries: PDO prepared statements, never string concat
- New output: always `htmlspecialchars()` on user data
- New files: add to Composer autoload if creating a class

Don't refactor the surrounding legacy code unless it's your explicit task.
Add clean new code alongside messy old code, not instead of it (yet).

## Running PHP Tools

```bash
# Syntax check a file (fast)
php -l src/legacy/PlayerLookup.php

# Run PHP linter/fixer
./vendor/bin/phpcs src/
./vendor/bin/phpcbf src/  # auto-fix

# Static analysis
./vendor/bin/phpstan analyse src/ --level=5

# Run tests
./vendor/bin/phpunit

# Dump autoload after adding new classes
composer dump-autoload
```

## PHP 7.x / 8.x Differences

```php
// Named arguments (PHP 8.0+)
array_slice(array: $arr, offset: 2, length: 5); // only if PHP 8.0+

// Nullsafe operator (PHP 8.0+)
$city = $user?->getAddress()?->getCity(); // only if PHP 8.0+

// Match expression (PHP 8.0+)
$result = match($status) { 'active' => 1, 'inactive' => 0, default => -1 };

// Union types (PHP 8.0+)
function process(int|string $id): void { }

// Check version before using
if (PHP_VERSION_ID >= 80000) { ... }
```

Check `phpversion()` or the project's `composer.json` `require.php` field to know
which version you're targeting before using modern syntax.
