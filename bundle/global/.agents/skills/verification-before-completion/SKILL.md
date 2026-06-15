---
name: verification-before-completion
description: "Use before completion or handoff to confirm verification evidence is fresh, relevant, and read; this is orchestrator discipline, not a legacy final-verifier agent."
---

# Verification Before Completion

Check whether the work can be honestly called complete. The orchestrator owns
this check directly; do not spawn a final-verifier agent for normal work.

## Inputs

- Changed files.
- Commands run after the last file change.
- Exit codes and key output.
- Any tests that were skipped or could not run.

## Rules

1. Fresh means the command ran after the last relevant file change.
2. Relevant means the command exercises the changed behavior or the nearest
   available contract.
3. Read the output before claiming success.
4. If files changed after verification, evidence is stale and must be rerun.
5. If a prerequisite is missing, report it as blocked or unable to run. Do not
   convert it into success.
6. Completion requires requested behavior done, fresh green checks, and no
   unhandled BLOCKING reviewer finding.

## Output

```text
VERIFICATION_CHECK: PASS|STALE|BLOCKED
- Fresh commands:
- Relevant coverage:
- Skipped/unavailable:
- Remaining blocker:
```
