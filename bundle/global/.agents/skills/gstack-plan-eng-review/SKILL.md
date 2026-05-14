---
name: gstack-plan-eng-review
description: >
  Use for architecture and plan review pressure before implementation. Applies gstack
  plan-eng-review: challenges architecture choices, data flow, failure modes, and test gaps.
  Stripped of Claude-specific host plumbing.
  Requires adversarial reasoning — always run with a premium reasoning model.
---

# Gstack Plan Eng Review

Apply gstack plan-eng-review as an architecture readiness and plan critique layer.
Do not execute telemetry/update scripts, `~/.claude/skills/...` paths, or host-specific routing.

## Source Note

> **This wrapper is the authoritative operational reference.**
> The baked-in pressure questions below are complete and self-contained — follow them directly.
>
> The raw vendored plugin at `~/.agents/workflows/plugins/gstack/plan-eng-review/SKILL.md`
> contains unresolved template/placeholder sections outside its preamble.
> **Do NOT load that file for operational execution.**
> It may be read for conceptual/background reference only; any template-style blocks
> in it must be ignored at runtime.

---

## Core Posture

**Challenge before commit.** The goal is to find flaws in the plan before any code is written.
Cheaper to redesign on paper than to refactor after implementation.

## Standard Pressure Questions

Apply all of these to any non-trivial implementation plan:

### Architecture
- Does this plan change the right thing, at the right layer?
- Is there a simpler path that achieves the same outcome?
- What existing abstraction does this break or duplicate?
- What assumption in this plan is most likely to be wrong?

### Data flow
- Who owns this data? Does this plan change ownership in a way that's appropriate?
- What happens to this data if the operation fails halfway through?
- Is there a state the system can reach that violates invariants?

### Failure modes
- What is the failure mode if this plan is wrong?
- Can this fail silently? How would you know it failed?
- Is there a partial-success scenario? Is it handled?
- What is the rollback path if this needs to be reverted?

### Boundaries and contracts
- Does this plan change any public interface, API, or contract?
- Are callers of the changed interface also updated?
- Does this plan introduce a dependency that didn't exist before?

### Test coverage
- What test would prove this plan is correct?
- What test would prove it hasn't broken anything?
- Is there a category of input or scenario the test plan doesn't cover?

### Scope
- Is this plan doing more than the task requires?
- Is there a scope that would achieve the same user value with less risk?

## When to Use

- Before implementing any non-trivial feature or refactor
- When an implementation plan involves multiple files or modules
- When the change touches an API contract or shared boundary
- When the user asks "does this plan look right?"

## Source

Conceptual reference only — **not for operational use at runtime**:
- `~/.agents/workflows/plugins/gstack/plan-eng-review/SKILL.md` (raw vendored; contains unresolved template sections — ignore any runtime/operational blocks)
