---
name: spec
model: gpt-5.4
description: >
  Lightweight spec-first workflow for complex features. Five phases before any code is written:
  Requirements clarification → Spec document → Technical plan → Task breakdown → Validation.
  Creates .codex/specs/NNN-feature-name.md as a durable spec artifact. Use /spec before /build
  on any feature that touches multiple files, has ambiguous requirements, or affects shared contracts.
  Prevents the most common class of build failures: implementing the wrong thing.
---

# Spec Workflow

Spec-first development prevents the most expensive kind of rework: implementing the wrong thing correctly.

Use `/plan` for targeted coding tasks that need an approval-ready build plan but do **not** need a durable repo spec. Use `/spec` when the output should live in `.codex/specs/` as a cross-session requirements artifact.

Use `/spec` before `/build` whenever:
- Requirements are ambiguous or could be interpreted multiple ways
- The feature touches 3+ files or crosses module boundaries
- The feature affects a public API, shared type, or database schema
- The user describes a goal but hasn't specified constraints or edge cases

---

## When NOT to Use

Skip `/spec` for:
- Small bug fixes with a clear root cause
- Cosmetic changes (styling, copy, labels)
- Changes where the diff is already fully specified
- Anything described as "quick" or "one-liner" that actually is
- Targeted coding tasks where `/plan` is sufficient and a durable spec artifact would be unnecessary overhead

---

## Five Phases

### Phase 1: Requirements Clarification

Before writing anything, extract the full requirement through targeted questions.

Ask **only the questions needed to resolve genuine ambiguity**. Do not ask questions the user already answered.

Key questions to answer:
- **What is the user's actual goal?** (not the feature, but the underlying need)
- **What does "done" look like?** (concrete success criteria)
- **What is explicitly out of scope?** (prevents scope creep during implementation)
- **What are the constraints?** (performance, backward compat, auth requirements)
- **What edge cases must be handled?** (empty state, error state, concurrent writes, large data)
- **Who calls this / who is affected?** (callers, consumers, downstream effects)

**Gate**: do not proceed to Phase 2 until requirements are unambiguous. If the user says "just figure it out", proceed with stated assumptions — document them explicitly.

### Phase 2: Spec Document

Create `.codex/specs/NNN-feature-name.md` (increment NNN from last spec, or start at 001).

```markdown
# Spec: [Feature Name]
*Created: YYYY-MM-DD | Status: draft → reviewed → implemented*

## Problem Statement
[1-2 sentences: what problem does this solve and for whom?]

## Requirements
### Must Have
- [concrete, testable requirement]
- [concrete, testable requirement]

### Must Not
- [explicit exclusion — prevents scope creep]
- [explicit exclusion]

### Assumptions
- [stated assumption — if wrong, revisit spec]

## Success Criteria
- [ ] [how to verify requirement 1 is met — a test scenario, not a code change]
- [ ] [how to verify requirement 2 is met]

## Out of Scope
- [explicitly excluded — document to prevent argument later]

## Edge Cases
- [empty state]: expected behavior
- [error state]: expected behavior
- [concurrent access]: expected behavior
- [large data / scale]: expected behavior

## Open Questions
- [question that must be resolved before implementation can proceed]
```

**Gate**: spec must have all "Must Have" items and at least 2 success criteria before proceeding.

### Phase 3: Technical Plan

Add a `## Technical Plan` section to the spec document.

```markdown
## Technical Plan

### Architecture Decision
[Which approach was chosen and why. What alternatives were rejected.]

### Files Affected
| File | Change type | Description |
|------|------------|-------------|
| `src/...` | new / modify / delete | what changes and why |

### Schema/Contract Changes
[Any new types, schema changes, or API contract changes. Cross-reference packages/types SST.]

### Integration Points
[Where does the new code plug in? What calls it? What does it call?]

### Risks
| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| [risk] | H/M/L | [mitigation] |
```

### Phase 4: Task Breakdown

Generate SQL todos from the spec. Each task must have enough context to be executed by a sub-agent without re-reading the spec.

```sql
INSERT INTO todos (id, title, description) VALUES
  ('spec-001-db', 'Create subscription table', 'Add subscriptions table in supabase/migrations/004_subscriptions.sql with columns: id, user_id, stripe_customer_id, status, tier. Enable RLS. See spec: .codex/specs/001-subscriptions.md'),
  ('spec-001-api', 'Create checkout route', 'New POST /api/checkout — creates Stripe Checkout session. Requires auth. Returns {url: string}. See spec: .codex/specs/001-subscriptions.md#Phase-2'),
  ...
```

**Rule**: every task description must name the file to create/modify and what specifically to do. Generic tasks like "implement the feature" are not acceptable — they will fail in sub-agent execution.

### Phase 5: Validation

Review the spec and task breakdown before handing to `/build`.

Validation questions:
1. Does every "Must Have" requirement map to at least one task?
2. Does every success criterion map to at least one test task?
3. Are there tasks with no dependency that can run in parallel?
4. Is there a task for updating `.wiki/features.md` if this adds a user-visible capability?
5. Is there a task for updating shared types if schema changes were made?
6. Are any edge cases left unhandled?

**Output**: present the spec document and task list to the user. **Wait for explicit confirmation before invoking /build.**

```
SPEC READY FOR REVIEW
=====================
[Paste the full spec document]

Proposed tasks:
1. [task-id]: [description]
2. [task-id]: [description]
...

Risks flagged: [list]
Open questions remaining: [list or "none"]

→ Confirm to proceed to /build, or provide corrections.
```

---

## Spec File Naming

```
.codex/specs/001-jwt-auth.md
.codex/specs/002-subscription-billing.md
.codex/specs/003-onboarding-wizard.md
```

Increment from the last existing spec. Use kebab-case slug matching the feature name.

---

## Integration with `/build`

After the user confirms the spec:
1. The spec document path is passed to the `patterns-explorer` in `/build` Phase 0
2. The `eng-plan-reviewer` reads the spec as the authoritative requirement (not the user's original message)
3. The `spec-reviewer` in the build loop validates that the implementation matches the spec
4. At build completion, update spec status from `draft` to `implemented`
