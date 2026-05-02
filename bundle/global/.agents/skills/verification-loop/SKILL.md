---
name: verification-loop
model: gpt-5.4
description: >
  Comprehensive post-implementation gate. Runs in sequence: build → type check → lint →
  test suite → security scan → diff review. Produces a structured VERIFICATION REPORT.
  Invoke with /verify after any significant code change, before any PR, and as the
  mandatory pre-completion gate in /build. Formalizes the Iron Law as a concrete sequence.
---

# Verification Loop

The Iron Law requires fresh verification evidence before any completion claim. This skill defines exactly what "verification" means and in what order to run it.

**Never say "tests pass" without running them. Never say "build succeeds" without seeing exit 0.**

---

## When to Invoke

- After every implementation phase in `/build`
- Before opening a PR or merging
- After any refactor or dependency change
- When the user asks "is this ready?" or "does this work?"
- After fixing a bug (verify the fix didn't break anything else)
- Invoke manually with `/verify`

---

## Verification Sequence

**Platform note (Windows)**: commands below use bash syntax for readability. On Windows PowerShell, replace `2>&1 | tail -30` with `2>&1 | Select-Object -Last 30`, and `| head -40` with `| Select-Object -First 40`. The `npm`, `pnpm`, `cargo` CLI tools work as-is in PowerShell.

Run these phases **in order**. If a phase fails, **STOP and fix before continuing**. Do not skip phases to report partial success.

### Phase 1: Build

```bash
# Pick the right command for the repo
npm run build 2>&1 | tail -30
# or
pnpm build 2>&1 | tail -30
# or
python -m build 2>&1 | tail -20
# or
cargo build 2>&1 | tail -20
```

**Gate**: exit code 0. Any build error = STOP. HMR acknowledgement is NOT a passing build.

**Frontend gate (strict)**: TypeScript `noEmit` alone does NOT pass this gate — it misses Vite transform-time errors. Must run the full build command and see exit 0.

### Phase 2: Type Check

```bash
# TypeScript
npx tsc --noEmit 2>&1 | head -40
# or
npx tsc --noEmit --pretty false 2>&1 | head -40

# Python
python -m mypy . 2>&1 | head -30
# or
pyright . 2>&1 | head -30
```

**Gate**: 0 new type errors introduced by the diff. Pre-existing errors in unmodified files may be noted but don't block.

### Phase 3: Lint

```bash
# JavaScript/TypeScript
npm run lint 2>&1 | head -40
# or
npx eslint src/ --max-warnings=0 2>&1 | head -30

# Python
ruff check . 2>&1 | head -30
# or
flake8 . 2>&1 | head -30

# Rust
cargo clippy 2>&1 | head -30
```

**Gate**: no new lint errors. Pre-existing warnings in unmodified code don't block.

### Phase 4: Test Suite

```bash
# Run full suite with coverage
npm test -- --coverage 2>&1 | tail -40
# or
pnpm test:coverage 2>&1 | tail -40
# or
pytest --tb=short --cov=src 2>&1 | tail -40
```

Record:
- Total tests: N
- Passed: N
- Failed: N  ← must be 0 for gate to pass
- Coverage: N% ← flag if below 80% on changed files

**Gate**: 0 failing tests. Coverage below 80% is a warning, not a block — but must be noted.

### Phase 5: Security Scan

```bash
# Check for secrets and hardcoded credentials
grep -rn "sk-\|api_key\s*=\|password\s*=\|token\s*=" --include="*.ts" --include="*.tsx" --include="*.py" --include="*.js" src/ 2>/dev/null | grep -v "test\|spec\|mock\|example\|\.env\|process\.env" | head -15

# Check for console.log left in production code
grep -rn "console\.log\b" --include="*.ts" --include="*.tsx" src/ 2>/dev/null | grep -v "test\|spec" | head -15

# Python: check for print() in non-debug code
grep -rn "\bprint(" --include="*.py" src/ 2>/dev/null | grep -v "test\|debug\|cli" | head -15
```

**Gate**: 0 hardcoded secrets. Flag console.log/print() in production paths as warnings.

### Phase 6: Diff Review

```bash
git diff HEAD --stat
git diff HEAD --name-only
```

Scan each changed file for:
- Unintended changes (files that shouldn't have been touched)
- Missing error handling in new code paths
- TODOs left in production code
- Commented-out code blocks

---

## Verification Report Format

After all 6 phases, produce this structured report — always, even for passes:

```
VERIFICATION REPORT
===================
Date: YYYY-MM-DD HH:MM
Scope: [feature/bug/refactor description]

Phase 1 — Build:     [PASS ✅ | FAIL ❌] [exit code, or error summary]
Phase 2 — Types:     [PASS ✅ | FAIL ❌] [N errors, or "0 new errors"]
Phase 3 — Lint:      [PASS ✅ | WARN ⚠️ | FAIL ❌] [N issues]
Phase 4 — Tests:     [PASS ✅ | FAIL ❌] [X/Y passed, Z% coverage on changed files]
Phase 5 — Security:  [PASS ✅ | WARN ⚠️] [findings or "clean"]
Phase 6 — Diff:      [CLEAN ✅ | REVIEW ⚠️] [X files changed, notes]

VERDICT: [READY ✅ | NEEDS WORK ❌ | BLOCKED 🚫]

Issues to fix before merge:
1. [Phase N] [description] [file:line]
2. ...

Warnings (non-blocking):
1. [description]
```

---

## Depth Variants

| Depth | Phases run | When |
|-------|-----------|------|
| `quick` | Build + Types only | Mid-session sanity check after small edit |
| `standard` | Phases 1–4 | After every implementation, before claiming done |
| `full` | All 6 phases | Before PR, after refactor, after dependency changes |

**Default is `standard`.** Run `full` before any merge. Run `quick` only when checking a compile-time fix.

---

## Fail-Fast Rule

If Phase 1 (Build) fails, stop. Do not run types, lint, or tests against a broken build — the output will be misleading. Fix the build, then restart the sequence from Phase 1.

If Phase 4 (Tests) has failures, do not open a PR. Fix the failures, then re-run Phases 4–6.
