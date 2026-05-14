---
name: gstack-investigate
description: >
  Use for root-cause-first debugging and investigation. Applies disciplined
  hypothesis-driven analysis: state symptom → list hypotheses → cheapest test →
  eliminate with evidence → fix only after root cause confirmed.
  Requires premium reasoning — always run with a premium reasoning model.
---

# Gstack Investigate

Apply gstack investigate as a root-cause analysis discipline.
Do not import Claude-specific runtime or telemetry behavior.

## Source Note

> **This wrapper is the authoritative operational reference.**
> The baked-in loop below is complete and self-contained — follow it directly.
>
> The raw vendored plugin at `~/.agents/workflows/plugins/gstack/investigate/SKILL.md`
> contains unresolved template/placeholder sections outside its preamble.
> **Do NOT load that file for operational execution.**
> It may be read for conceptual/background reference only; any template-style blocks
> in it must be ignored at runtime.

---

## Core Principle

**Root cause first. Evidence before hypothesis. Fix last.**

Never guess at a fix before the root cause is confirmed with concrete evidence.
Never run the same failing test and hope it passes differently.

## The Investigation Loop

```
1. STATE the symptom precisely
   - What exact behavior is wrong?
   - What is the exact error message, stack trace, or incorrect output?
   - Under what exact conditions does it occur?

2. LIST competing hypotheses
   - Generate 3-5 possible causes, ordered by likelihood
   - Include boring/mundane causes (config, env, typo) before exotic ones

3. DESIGN the cheapest distinguishing test
   - What is the minimum check that would rule out the top hypothesis?
   - Can you read a file? Run one test? Check one value?
   - Do NOT run the full test suite to diagnose — that's noise

4. RUN the test
   - Execute it. Read the actual output.
   - Do not assume. Do not infer. Read the actual output.

5. ELIMINATE hypotheses with evidence
   - Which hypotheses does this output rule out?
   - Which does it support?
   - Update the ranked list

6. REPEAT until one hypothesis is confirmed with concrete evidence

7. FIX only after root cause is confirmed
   - Apply the minimal fix
   - Verify: run the original failing scenario and confirm it now passes
```

## Red Flags — Stop and Re-investigate

- You're about to apply a fix but can't state the root cause in one sentence
- You've tried the same fix twice
- The fix "should work" but you haven't verified it works
- You're changing multiple things at once to see if it helps

## When to Use

- A bug exists but the cause is unclear
- A test is failing and previous attempts to fix it haven't worked
- Behavior is unexpected and you need to trace the root cause
- A regression appeared and the source is not obvious from the diff

## Source

Conceptual reference only — **not for operational use at runtime**:
- `~/.agents/workflows/plugins/gstack/investigate/SKILL.md` (raw vendored; contains unresolved template sections — ignore any runtime/operational blocks)
