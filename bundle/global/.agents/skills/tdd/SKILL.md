---
name: tdd
description: >
  Test-Driven Development workflow. Invoke when writing new features, fixing bugs, or refactoring.
  Enforces Red → Green → Refactor with git checkpoint commits and 80%+ coverage gate.
  Invoke with /tdd or activate inside /build for test-first discipline.
  Implementers receive concrete TDD instructions; orchestrator verifies RED and GREEN outputs.
---

# TDD Workflow

Writing tests first forces a concrete spec before any implementation. It is not slower — it removes rework by making failure modes explicit before you write code.

## When to Invoke

- New features or functionality
- Bug fixes (the reproducer test **is** the spec)
- Refactoring existing code (tests prove behavior is preserved)
- Any API endpoint, service function, or component with logic
- Explicitly requested by the user with `/tdd`

---

## Core Law

**Tests BEFORE code. No exceptions.**

If an implementer writes production code before a failing test exists, it is a policy violation. Stop. Write the test. Confirm it fails. Then write the code.

---

## Red → Green → Refactor

### Phase 1: RED — Write a failing test

Write the smallest test that captures the intended behavior. Run it. Confirm it fails **for the right reason**.

```bash
# Run only the new test file — not the whole suite
npm test -- --testPathPattern="path/to/your.test"
# or
pnpm test path/to/your.test
# or
python -m pytest path/to/test_file.py -k "test_function_name"
```

**RED gate validation:**
- ✅ Valid RED: test fails because the behavior doesn't exist yet
- ❌ Not RED: test fails due to syntax error, broken setup, or missing import — fix those first, then re-confirm RED
- ❌ Not RED: test was written but never run — running is mandatory

**Git checkpoint after RED:**
```bash
git add -p
git commit -m "test: add reproducer for <feature or bug>"
```

### Phase 2: GREEN — Write minimal code

Write the **smallest** code change that makes the test pass. No extras. No refactoring yet.

```bash
# Re-run the same test — must see PASS
npm test -- --testPathPattern="path/to/your.test"
```

**GREEN gate validation:**
- ✅ Valid GREEN: test output shows PASS with the previously failing test now green
- ❌ Not GREEN: "I think it works" — run it and read the output

**Git checkpoint after GREEN:**
```bash
git add -p
git commit -m "fix: <feature or bug>"
```

### Phase 3: REFACTOR — Clean up while green

Now improve the code: remove duplication, improve naming, simplify logic, optimize. After every change:

```bash
npm test  # Keep all tests green — any failure here means the refactor broke behavior
```

**Git checkpoint after REFACTOR:**
```bash
git commit -m "refactor: clean up after <feature or bug> implementation"
```

---

## Coverage Gate

After the full TDD cycle, verify coverage:

```bash
npm run test:coverage
# or
pnpm test:coverage
# or
pytest --cov=src --cov-report=term-missing
```

**Target: 80% minimum** across unit + integration combined. If under 80%, add tests for:

1. **Error paths** — what happens when the external call fails? DB is unavailable? Input is null?
2. **Edge cases** — empty input, zero, negative, max value, concurrent writes
3. **Boundary conditions** — off-by-one, type coercions, length limits

---

## Test Types by Layer

| Layer | Test type | Preferred tool |
|-------|-----------|---------------|
| Pure functions, utilities | Unit | Jest / Vitest / pytest |
| API endpoints, HTTP handlers | Integration | Supertest / httpx / FastAPI TestClient |
| Database operations | Integration (test DB) | Prisma test utils / SQLite in-memory |
| User flows, browser | E2E | Playwright / Cypress |
| React components | Component | React Testing Library |

**Rule**: prefer integration tests over unit tests for service-layer code. Unit tests for pure logic only — if you need a mock to make a unit test work on a service function, write an integration test instead.

---

## Instructions for Implementers

When `/tdd` is active, pass this block to every implementer sub-agent:

```
You are implementing in TDD mode. For every function, endpoint, or component:

1. Write a failing test FIRST (no production code yet)
2. Run the test — confirm RED output (paste the failure line)
3. Write minimal code to reach GREEN
4. Run the test again — confirm GREEN output (paste the passing line)
5. Refactor if needed, keep all tests green
6. Create git checkpoints after RED and after GREEN

Do not claim a feature is implemented until you have seen GREEN output and included it in your response.
```

---

## Anti-patterns to Reject

| Anti-pattern | Why it fails |
|-------------|-------------|
| Writing tests after implementation | You're testing what you wrote, not what you specified. Coverage but no protection. |
| Tests that always pass | `expect(true).toBe(true)` — green theater. Catches nothing. |
| Mocking the thing under test | You're testing your mock, not the code. Write an integration test instead. |
| Skipping RED validation | "It obviously should fail" is not evidence. You must see the failure output. |
| Coverage theater | Tests that execute code but never assert specific values or behaviors. |
| Testing implementation details | Test observable behavior, not internal function calls. Refactoring should not break tests. |
