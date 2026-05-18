---
name: test-gen
description: Generate tests with build-verified iteration loop. Use when the user types /test-gen or asks to generate, add, or write tests. Inspired by Amazon Q's test-iterate pattern.
---

# /test-gen

Build-verified test generation with iteration loop. Tests are not "done" until they pass.

## Phase 1 — Analyze test target

1. Identify the file(s) or feature to test
2. Read existing test patterns in the repo (test runner, framework, directory structure, naming conventions)
3. Read the source code to understand the API surface, edge cases, and error paths
4. Check `.kit/context/memory.md` for repo-specific test conventions

## Phase 2 — Generate tests (iteration loop, max 5 rounds)

Use `test-loop-runner.ps1` as the mechanical runner between fixes. The agent reads log files
and applies fixes; the tool handles execution and structured output.

For each round:
1. **Generate**: Write test file(s) following the repo's existing patterns
2. **Run**: Execute the test command via `test-loop-runner.ps1`:
   ```powershell
   pwsh ~/.agents/tools/test-loop-runner.ps1 `
     -SessionId "$CLAUDE_SESSION_ID" `
     -TestCommand "npm test" `
     -TestFile "path/to/test-file.test.ts" `
     -MaxRounds 1
   ```
   Or let the tool manage the full loop from the start with `-MaxRounds 5`.
3. **Analyze**: Read the log at `{session_dir}/test-round-{N}.log`. Categorize the failure:
   - Syntax errors → fix immediately in the test file
   - Import / module path errors → fix require/import statements
   - Assertion failures → decide: wrong expectation or real bug in source?
     - If wrong expectation: fix the test
     - If real bug: report to user, do NOT silently change source
   - Missing mocks/fixtures → add them
   - Timeout / async handling → reduce scope or add proper await/done handling
4. **Fix**: Apply targeted edits based on the failure analysis
5. **Re-run**: Go back to step 2

Exit the loop when:
- All tests pass (exit code 0) → record verification gate:
  ```powershell
  pwsh ~/.agents/tools/workflow-evidence.ps1 `
    -SessionId "$CLAUDE_SESSION_ID" `
    -AddVerification "test-gen pass" `
    -WithExitCode 0 `
    -WithCommand "<test command used>"
  ```
- Max 5 rounds reached without passing → report remaining failures to user with the
  last log path. Do NOT claim tests pass.

## Phase 3 — Coverage report (if available)

If the repo has a coverage tool configured:
1. Run coverage report
2. Identify uncovered lines in the target file(s)
3. Suggest (but do NOT auto-generate) additional tests for uncovered paths — ask user first

## Phase 4 — Verification gate

Run the full test suite one final time (not just the new file). Record evidence:

```powershell
pwsh ~/.agents/tools/workflow-evidence.ps1 `
  -SessionId "$CLAUDE_SESSION_ID" `
  -AddVerification "<full test command>" `
  -WithExitCode $LASTEXITCODE `
  -WithCommand "<full test command>"
```

The `-WithExitCode` argument must be 0. If the full suite fails, do not record and
surface the failure to the user.

## What NOT to do

- Do NOT generate tests without running them — single-shot generation is explicitly rejected
- Do NOT claim tests pass without running them (Iron Law)
- Do NOT modify source code to make tests pass unless the user explicitly asks
- Do NOT generate tests for files the user did not ask about
- Do NOT skip the iteration loop for "simple" tests — always verify at least one round
- Do NOT reuse a prior round's log as evidence for a later claim
