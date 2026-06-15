---
name: silent-failure-hunter
description: "Use when a diff adds or changes async work, try/catch, fallbacks, CLI exit handling, logging, filesystem/network/subprocess calls, or other paths where failures can be swallowed."
---

# Silent Failure Hunter

Find real cases where failure becomes false success, an empty result, a vague
log line, or a lost exit code. This is a focused review lens, not a broad code
quality reviewer.

## Check

- Empty or near-empty `catch` blocks.
- `.catch()` handlers that return `[]`, `null`, `undefined`, `false`, or success.
- Broad catches that log but do not rethrow, return an error value, or mark the
  operation failed.
- CLI scripts that print an error but exit `0`.
- Missing `await` or unobserved promises in critical work.
- Fallbacks that hide unconfigured services, missing credentials, or unavailable
  dependencies.
- Filesystem, network, database, or subprocess failures without useful context.
- Partial writes where step two can fail after step one succeeds.
- Tests that only cover the success path for newly added error handling.

## Reporting Rules

- Report only confirmed issues in changed or directly relevant code.
- Include `file:line` and the exact failure mode.
- Prefer one consolidated finding for repeated identical patterns.
- Do not report style opinions, speculative edge cases, or intentional test
  doubles.

## Output

```text
SILENT_FAILURE_FINDING: BLOCKING|NON_BLOCKING
FILE:
WHAT:
IMPACT:
FIX:
```
