---
name: kit-init
description: Use when .kit/ is missing or repo-local agent context needs setup. Creates a minimal indexed kit scaffold from code evidence.
---

# Kit Init Skill

Bootstrap the smallest useful `.kit/` scaffold from real repo evidence.

## When To Run

- `.kit/` does not exist.
- `pre-session.ps1` reports `KIT: MISSING`.
- The user asks to set up or refresh repo-local kit context.

## Default Output

Create only these default files unless the repo clearly needs more:

```text
.kit/
|-- context/
|   |-- patterns.md
|   `-- workflow-briefs/
|       |-- workflow-explorer.md
|       |-- workflow-implementer.md
|       `-- workflow-ui-qa.md
`-- workflows/
```

Do not create legacy memory, handoff, reflection, or role-context files by
default. Preserve them if they already exist.

## What To Write

### `patterns.md`

Write compact repo facts that actually help future agents:

- build/test commands that were verified
- directory ownership and placement rules
- recurring implementation patterns worth copying
- real architecture boundaries with file evidence

Keep it under 80 lines. Every durable claim needs a file path or command
evidence. Do not add generic advice.

### Workflow Briefs

Create only:

- `workflow-explorer.md`: where to start looking and which files are canonical
- `workflow-implementer.md`: implementation conventions and verification command
- `workflow-ui-qa.md`: UI routes, fixture data, and user-flow checks, if relevant

Each brief should be under 120 lines and may say `No repo-specific guidance
found yet.` Do not create reviewer, skeptic, prompt-synthesizer, or role-memory
briefs by default.

### Workflow Overrides

Leave `.kit/workflows/` empty unless the repo has a real, cited workflow rule
that differs from the global skill. Most repos do not need overrides.

## Re-Run Mode

If `.kit/` already exists:

1. Read only `patterns.md` and the three lean workflow briefs unless the user
   explicitly asks to migrate old memory.
2. Update surgically from current code evidence.
3. Do not bulk-read handoffs, history, reflections, or legacy role memory.
4. Do not overwrite optional compatibility files.

## Output

End with:

```text
KIT_INIT:
- patterns.md: created|updated|skipped
- workflow briefs: explorer=<status>, implementer=<status>, ui-qa=<status>
- optional compatibility files touched: none|<list>
- verification evidence: <commands or "not applicable">
```
