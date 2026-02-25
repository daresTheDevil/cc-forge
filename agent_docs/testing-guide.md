---
last_verified: YYYY-MM-DD
last_verified_by: [session-id or engineer-name]
drift_check: compare against package.json test scripts — verify test commands and coverage config are current
---

# Testing Guide

> Template — populate during `/discuss` session.
> Replace all `[FILL IN]` sections. Delete this instruction line when done.

## Test Philosophy

- Tests document behavior, not implementation
- Every test name describes WHAT is tested and WHEN
- Test the contract (inputs → outputs), not the internals
- One logical assertion per test
- Arrange → Act → Assert, always

## Test Commands

```bash
# Run all tests
[FILL IN: bun run test]

# Run tests with coverage
[FILL IN: bun run test:coverage]

# Run a specific file
[FILL IN: bun run test src/path/to/file.test.ts]

# Watch mode (during development)
[FILL IN: bun run test --watch]
```

## Coverage Targets

| Domain | Current | Target |
|--------|---------|--------|
| [FILL IN: API routes] | [FILL IN]% | [FILL IN]% |
| [FILL IN: Business logic] | [FILL IN]% | [FILL IN]% |
| [FILL IN: DB layer] | [FILL IN]% | [FILL IN]% |

## Framework and Patterns

**Framework:** [FILL IN: Vitest / Jest / PHPUnit / pytest]

### Standard Test Structure

```typescript
// [FILL IN: adapt to actual framework]
describe('[ComponentOrFunction]', () => {
  describe('when [condition]', () => {
    it('[does what]', async () => {
      // Arrange
      const [setup] = [FILL IN]

      // Act
      const result = await [functionUnderTest]([input])

      // Assert
      expect(result.[field]).toBe([expected])
    })
  })
})
```

## Mocking Strategy

[FILL IN: How are dependencies mocked?]

- **Database:** [e.g., in-memory SQLite, mock functions, test containers]
- **External APIs:** [e.g., vi.mock, nock, MSW]
- **File system:** [e.g., memfs, temp dirs]
- **Time:** [e.g., vi.useFakeTimers()]

## Test Data

[FILL IN: Where does test data come from? How are fixtures managed?]

- **Factories:** [e.g., src/tests/factories/]
- **Fixtures:** [e.g., src/tests/fixtures/]
- **Seeding:** [e.g., how to seed test databases]

## CI/CD Integration

[FILL IN: How do tests run in CI?]

- **Trigger:** [on every PR / on push to main / etc.]
- **Fail condition:** [any test failure / coverage drop below X% / etc.]
- **Report location:** [where test reports are published]

## What NOT to Test

[FILL IN: Things that should not be unit tested in this codebase — avoids wasted effort]

- Third-party library internals
- [FILL IN: other project-specific exclusions]

## Known Test Gaps

[FILL IN: Areas with known insufficient coverage that should be addressed]

| Area | Gap | Priority |
|------|-----|----------|
| [FILL IN] | [FILL IN] | [high/med/low] |
