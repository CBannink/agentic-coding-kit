# GitHub Copilot Instructions — Caspar Bannink Agentic Coding Kit

Copilot Chat / Copilot CLI reads this file. Every session starts here.
The global workflow skills under `~/.agents/skills/` are the canonical
phase content — this file handles host constraints only.

## Host constraints (critical — modify your behavior)

- Subagent output is NOT streamed (issue #2265) — user sees nothing until
  the agent completes. Shell stdout is buffered (issue #1127).
- Per-command timeout is ~5-6 minutes. Each leaf agent must complete in <5 min.
- **YOU are the orchestrator.** Never spawn goal-orchestrator or build-orchestrator
  — they run silently. Only delegate to leaf agents.
- Emit `[WORKFLOW N/TOTAL] Spawning <agent>...` before every spawn so the user
  sees forward motion.

## ONE RULE (the rest is context)

**Before ANY Edit or Write call:**

```bash
git diff --name-only HEAD
```

| Count | Action |
|---|---|
| 1 existing file, no new files | ✅ Inline Edit allowed |
| >1 file OR any new file | 🚫 STOP. Spawn `workflow-implementer`. |

This is not a preference. Inline multi-file edits bypass the review harness.

## Tier

| Tier | When | Action |
|---|---|---|
| ISOLATED | 1 file | Inline Edit |
| TARGETED (default) | 2+ files | Spawn `workflow-implementer` + 1 reviewer + final-verifier |
| FULL | Cross-cutting, auth, schema | Plan first, then 5-7 agents |

## Workflow routing

Read the skill, execute inline. Emit progress lines before every spawn.

| Intent | Skill to read |
|---|---|
| Build / implement / fix / refactor | `~/.agents/skills/build/SKILL.md` |
| Autonomous multi-step goal | `~/.agents/skills/goal/SKILL.md` |
| Review / audit | `~/.agents/skills/review/SKILL.md` |
| Debug / root cause | `~/.agents/skills/investigate/SKILL.md` |
| Plan / scope | `~/.agents/skills/plan/SKILL.md` |
| Restructure | `~/.agents/skills/refactor/SKILL.md` |
| UI / visual redesign | `~/.agents/skills/redesign/SKILL.md` |
| Security audit | `~/.agents/skills/security-review/SKILL.md` |

## Lifecycle (all workflows)

```
START:  pwsh ~/.agents/tools/pre-session.ps1 -Mode <mode> -Task "<task>"
GATE:   pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "<gate>"
END:    pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove
```

## Iron Law

No completion claim without **fresh** verification evidence. Exit 0 from the exact
verification command. Not "tests probably pass."

## Core rules

1. Respect `.kit/` layout — memory in `.kit/context/`, handoffs in session-state.
2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.
3. Self-improvement runs automatically in post-session. Only call `/reflect`
   manually when reflections.md has 5+ unaddressed entries needing judgment.