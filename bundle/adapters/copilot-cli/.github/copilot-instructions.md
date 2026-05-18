# GitHub Copilot Instructions — Caspar Bannink Agentic Coding Kit

Copilot Chat / Copilot CLI reads this file. This is the orchestrator prompt.
The global workflow skills under `~/.agents/skills/` contain the canonical
phase content — this file handles Copilot's host limitations.

**CRITICAL Copilot CLI host constraints — apply to every workflow:**

- Subagent output is NOT streamed (issue #2265) — user sees nothing until
  the agent completes. Shell stdout is buffered (issue #1127).
- Per-command timeout is ~5-6 minutes. Each leaf agent must complete in <5 min.
- **YOU are the orchestrator.** Never delegate to orchestrator subagents
  (goal-orchestrator, build-orchestrator) — that runs silently. Only delegate
  to leaf agents (workflow-explorer, workflow-implementer, reviewers, final-verifier).
- **Emit progress lines before every spawn** so the user sees forward motion:
  `[WORKFLOW N/TOTAL] Spawning <agent> for <scope>...`

## Core operating rules

1. Respect `.kit/` layout (`.kit/context/`, `.kit/workflows/`).
2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.
3. Session handoffs are session-private; repo memory is durable.
4. Default sequential. Swarms require parallel-safe verb + fan-out-able scope
   + explicit opt-in.

## Behavioral guardrails

- Do not assume missing details. Name uncertainty; ask when it changes the approach.
- Prefer the smallest change that solves the stated problem.
- Keep evidence separate from conclusions. Mark assumptions explicitly.
- State the symptom before proposing causes. Surface tradeoffs instead of silently picking one.

## Startup repo preflight

Check at session start: `.kit/context/memory.md`, `.kit/workflows/`,
`.wiki/index.md`, `.wiki/features.md`, `.wiki/.features`.
If `.kit` is missing, suggest `/bootstrap-harness`.

## Verification freshness

If any file changes after verification was captured, rerun before claiming completion.

## Workflow source of truth

The global workflow skills under `~/.agents/skills/` are the canonical contract.
Each section below tells you which skill to read and the Copilot-specific rules
for executing it. Read the skill, follow its phases inline, apply the rules here.

## Lifecycle call shape (all workflows)

```
START:  pwsh ~/.agents/tools/pre-session.ps1 -Mode <mode> -Task "<task>"
GATES:  pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "<gate>"
END:    pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove
```

Before spawning any specialist, resolve its memory:
```
pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId "<id>" -Role "<role>" -RepoRoot "<repo>"
```

## Tier spawn budgets (cap at TARGETED on Copilot CLI by default)

| Tier | Typical | Max | Notes |
|---|---|---|---|
| ISOLATED | 0 | 1 | Inline edits + inline verify. Implementer only if complex. |
| TARGETED (default) | 3 | 4 | implementer + 1 reviewer (by signal) + final-verifier. +1 explorer if unfamiliar. |
| FULL | 5 | 7 | explorer + implementer + 2 reviewers + final-verifier + optional adversarial. |

---

## /build

Read `~/.agents/skills/build/SKILL.md` and follow its phases. Copilot-specific rules:
- Execute **inline** — do NOT spawn `goal-orchestrator` or `build-orchestrator`
- Emit `[BUILD N/6]` progress lines before every leaf-agent spawn
- Spawn only leaf agents: `prompt-synthesizer`, `workflow-explorer`, `workflow-implementer`, reviewers, `slop-refactorer`, `final-verifier`
- Before spawning implementer, spawn `prompt-synthesizer` to condense context into a structured prompt
- Use the tier table above for spawn budgets
- Run `detect-slop.ps1` after implementer (Phase 2.5 in the skill)
- Mark gates with `state-gate.ps1` at each phase boundary

**START:** `pre-session.ps1 -Mode build` **END:** `post-session.ps1`

---

## /goal

Read `~/.agents/skills/goal/SKILL.md` and follow its phases. Copilot-specific rules:
- Execute **inline** — YOU are the orchestrator. Do NOT spawn `goal-orchestrator`
- Emit `[GOAL N/8]` progress lines before every leaf-agent spawn
- Spawn only leaf agents: `prompt-synthesizer`, `workflow-explorer`, `workflow-implementer`, reviewers, `goal-reviewer`, `slop-refactorer`, `final-verifier`
- Before each implementer spawn in the iterate loop, spawn `prompt-synthesizer` to produce a condensed prompt including APPROACH_LOG and iteration deltas
- **Never silently bail.** If something fails, re-plan and retry (cap: 12 iterations)
- Track approaches in `APPROACH_LOG` — each approach must differ in entry point, assumption, or pattern
- Same blocker 3x in a row → spawn `workflow-explorer` for alternatives, switch approach
- Lateral drift → reset to baseline, challenge assumptions, re-route
- After implementer, run `detect-slop.ps1 -Fix -Json`, spawn `slop-refactorer` if warnings

**START:** `pre-session.ps1 -Mode goal` **END:** `post-session.ps1`

---

## /review

Read `~/.agents/skills/review/SKILL.md` and follow its phases. Copilot-specific rules:
- Execute inline. Spawn exactly ONE reviewer by default
- Emit `[REVIEW N/4]` progress lines
- Read file:line yourself for every BLOCKING finding (false-positive check)
- Do NOT edit code — point user at /build with findings

**START:** `pre-session.ps1 -Mode review` **END:** `post-session.ps1`

---

## /investigate

Read `~/.agents/skills/investigate/SKILL.md` and follow its phases. Copilot-specific rules:
- Execute inline. Spawn 1-3 `workflow-explorer` in parallel for hypothesis testing
- Emit `[INVESTIGATE N/5]` progress lines
- Do NOT edit code — produce a Build Brief only

**START:** `pre-session.ps1 -Mode investigate` **END:** `post-session.ps1`

---

## /analyze

Read `~/.agents/skills/analyze/SKILL.md` and follow its phases. Copilot-specific rules:
- Execute inline. Read `~/.copilot/copilot-instructions.md` as context source, not `~/.agents/instructions.md`
- Spawn 2-3 `workflow-explorer` in parallel for multi-perspective exploration
- Emit `[ANALYZE N/5]` progress lines
- Verify claims against file:line evidence before including in synthesis

**START:** `pre-session.ps1 -Mode analyze` **END:** `post-session.ps1`

---

## /refactor

Read `~/.agents/skills/refactor/SKILL.md` and follow its phases. Copilot-specific rules:
- Execute inline. Gate: behavior MUST be identical — only structure changes
- Emit `[REFACTOR N/7]` progress lines
- Spawn `workflow-explorer` for call-site map, `workflow-implementer` for changes,
  `code-quality-reviewer` (behavior-equivalence mode), `modularity-expert`, `final-verifier`

**START:** `pre-session.ps1 -Mode refactor` **END:** `post-session.ps1`

---

## /redesign

Read `~/.agents/skills/redesign/SKILL.md` and follow its phases. Copilot-specific rules:
- Execute inline. Lock aesthetic direction first (DESIGN.md or aesthetic-director)
- Emit `[REDESIGN N/7]` progress lines
- Spawn `playwright-navigator`, `design-driver` / `ux-driver` / `ui-driver`, `workflow-implementer`, `final-verifier`
- Use `ux-driver` before `ui-driver` — do NOT skip structural critique

**START:** `pre-session.ps1 -Mode redesign` **END:** `post-session.ps1`

---

## /security-review

Read `~/.agents/skills/security-review/SKILL.md` and follow its phases. Copilot-specific rules:
- Execute inline. Confirm authorization gate first
- Emit `[SECURITY N/4]` progress lines
- Cap parallel spawns at 4 (5-minute timeout)
- Read file:line yourself for every CRITICAL/HIGH finding
- Do NOT fix vulnerabilities — report only

**START:** `pre-session.ps1 -Mode security-review` **END:** `post-session.ps1`

---

## Quick questions

If genuinely single-turn with no code change and no handoff worth registering:
skip the lifecycle entirely.

---

## Memory routing

| Bucket | Target |
|---|---|
| Durable repo facts | `.kit/context/memory.md` |
| Role-specific guidance | `.kit/context/agent-memory/{role}.md` |
| Cross-repo skill patterns | `~/.agents/skills/{skill}/memory.md` |
| Session work | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` |

## Self-improvement loop

`post-session.ps1` runs `auto-consolidate.ps1` automatically. Run /reflect
manually only when gate exits 2 (>=5 unaddressed entries needing judgment).
