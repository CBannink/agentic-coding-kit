# Features — Caspar Bannink Agentic Coding Kit

User-visible capabilities catalog. Updated 2026-05-18.

## Multi-host adapter system

Adapters for **Claude Code**, **Copilot CLI**, **OpenCode**, **Codex CLI**, and **generic** (Aider/Cline/Cursor/Continue).
Each adapter translates the shared workflow contracts into host-native execution.

## Core workflow commands

| Command | What it does | Swarm? |
|---|---|---|
| `/bootstrap-harness` | Goal-conditioned repo init — detects conventions, scaffolds .kit/ + .wiki/, iterates until all outcomes exist | sequential w/ light parallel |
| `/plan` | Clarify scope, map files, trace blast radius, plan.md, approval gate | sequential |
| `/build` | Implement → review → verify pipeline. Main session orchestrates; spawns workflow agents + specialists per phase. | sequential (parallel-reviewers OK at FULL tier) |
| `/review` | Hierarchical: surface → interactions → synthesis → adversarial → false-positive verify | sequential, optional swarm-review |
| `/goal` | Autonomous goal-achievement loop. Classifies goal type (CODE/DESIGN/INVESTIGATION/REFACTOR/MULTI), convergence loop with 6-iteration cap, stuck/rollback/lateral-drift detection, DESIGN pipeline embedded | **swarm-eligible** |
| `/analyze` | Multi-angle research/synthesis via gstack investigate/office-hours/plan-eng-review | sequential |
| `/investigate` | Hypothesis-driven root-cause-first debugging | sequential |
| `/refactor` | Principle-driven restructuring with consequence tracing | sequential |
| `/redesign` | Greenfield UI / multi-component visual rebuild | **swarm-eligible** — fan out one designer per screen |
| `/security-review` | Adversarial audit by attack class | **swarm-eligible** — fan out one agent per attack class |

## Goal orchestrator — autonomous convergence loop

**`/goal`** is the kit's most capable workflow. It:

1. Classifies goal type (CODE / DESIGN / INVESTIGATION / REFACTOR / MULTI)
2. Picks the right toolchain for that type
3. Runs a convergence loop with:
   - **6-iteration soft cap** — re-plans after hitting it
   - **12-iteration hard cap** — forces escalation
   - **Stuck detection** — 3 same-signature failures = escalate
   - **Rollback-oscillation detection** — same rollback triggered twice = escalate
   - **Lateral-drift detection** — goal divergence across iterations
4. Includes a full **DESIGN pipeline**: aesthetic-director → playwright-navigator → playwright-runner → ux-driver → ui-driver → visual-diff
5. Applies **dynamic model selection** via `model-selector.ps1` (scope-aware + trust-aware)
6. Runs **goal-reviewer** before Iron Law to independently verify semantic goal achievement

## Prompt synthesizer agent

Condensed prompts between phases so subagents don't receive bloated context.
Deduplicates context, preserves key constraints and success criteria.
Spawned at phase boundaries by the goal orchestrator and other workflow agents.

## AI slop refactoring

Automatic slop detection + cleanup on EVERY build cycle. Two-step:

1. `detect-slop.ps1 -Fix` runs mechanically (10 detectors: comment bloat, commented-out code, empty catch, oversized files/functions, generic names, deep nesting, trailing whitespace, excess blank lines)
2. `slop-refactorer` agent spawns for judgment-level fixes (comment pruning, naming, function extraction) — preserves behavior

Runs at [BUILD 2.5] — after implementation, before review.

## Tier-based agent budget system

| Tier | Agents | When |
|---|---|---|
| INLINE | 0 | Single-line edits, trivial fixes |
| TARGETED | 3-4 | Default for most work |
| FULL | 5-7 | Multi-file features, complex changes |
| SWARM | 24 | Opt-in only, parallel-safe scope |

Swarm fires only when: verb is parallel-safe + scope is fan-out-able + opted in.

## 17 specialist + workflow agents

**Workflow agents** (transport layer): workflow-explorer, workflow-implementer, workflow-reviewer, workflow-skeptic, workflow-ui-qa

**Specialists** (domain experts): code-quality-reviewer, security-reviewer, modularity-expert, adversarial-reviewer, final-verifier, qa-reviewer, spec-reviewer, playwright-navigator, ux-driver, ui-driver

**Orchestrators**: goal-orchestrator, pr-reviewer

## Self-improvement reflection loop

- 11 failure detectors fire at post-session
- **Phase 1** — auto-consolidate: dedup, archive promoted, drop stale, promote additive patterns
- **Phase 2** — compress-memory: archive old sessions, age history, dedup
- **Phase 2b** — harness-propose: 5+ recurring kit-level failures → writes proposal (never auto-applies)
- **Phase 3** — reflect-trigger: 5+ unaddressed = mandatory `/reflect` before next session

## Protocol-layer hook enforcement

Deterministic hooks that fire at every tool call (cannot be skipped):
- Dangerous filesystem ops blocked (`rm -rf /`, `sudo rm`, `chmod 777`)
- Force-push to main/master blocked without confirmation
- Git commit requires verification evidence gate
- Test commands auto-mark verification gate
- First-edit-per-file reminder for wiki-resolver
- Wiki-existence check blocks edits in unscaffolded repos

## Lint-gated editing

PostToolUse hook runs a language-appropriate linter after every file edit.
If syntax errors are detected, the agent gets immediate feedback and self-corrects.
Supported: JS/TS (ESLint), Python (py_compile), Ruby, Go (gofmt), Rust (rustfmt), PowerShell (PSParser), JSON.
Only uses linters already on PATH — installs nothing.

## Context bloat guard

Pre-session checker that scans all kit-managed context files against soft/hard line-count limits. Auto-triggers `compress-memory.ps1` or `auto-consolidate.ps1` when hard limits are exceeded.

| File | Soft | Hard | Auto-action |
|---|---|---|---|
| memory.md | 300 | 500 | Dedup via compress-memory |
| reflections.md | 50 | 100 | Auto-consolidate |
| handoffs.md | 200 | 400 | Trim oldest entries |
| history.md | 300 | 600 | Archive old entries |
| Skill memory | 200 | 400 | Flag for /reflect |

## Memory inbox (memory-review skill)

Observations and patterns discovered during sessions go into an inbox.
The developer explicitly reviews, approves, or rejects each item before it gets applied.
Actions: `collect`, `list`, `approve`, `reject`, `flush`.
Skill: `/memory-review`

## Test-iterate loop (test-gen skill)

Amazon Q-inspired build-verified test generation. Tests are not "done" until they pass.
Generates tests → runs build → analyzes failures → fixes → re-runs, max 5 rounds.
Single-shot test generation is explicitly rejected.

## Mode profiles

Roo Code-inspired mode-level tool and file restrictions per agent role.

| Mode | Write | Bash | Purpose |
|---|---|---|---|
| debug | None | Read-only | Root cause investigation |
| architect | Docs only | No | Design and documentation |
| reviewer | None | No | Code review, findings only |
| implementer | Full | Full | Implementation |
| explorer | None | Read-only | Codebase navigation |
| security-reviewer | None | No | Security audit |

Repos can override via `.kit/modes/{mode}.json`.

## Dynamic model selection

`model-selector.ps1` picks the right model per agent based on scope + role.
Scope-aware + trust-aware — downgrades noisy agents via `agent-trust-scorer.ps1`.
Cross-provider ensemble routing on Copilot CLI for output diversity.
Configurable via `MODEL_FAST` / `MODEL_BALANCED` / `MODEL_PREMIUM` env vars or `MODEL_MAP_FILE`.

## Per-CLI enforcement matrix

| CLI | Slash commands | Sub-agents | Skills | Pre/Post hooks | Lifecycle |
|---|---|---|---|---|---|
| Claude Code | ✅ | ✅ | ✅ | ✅ | ✅ |
| OpenCode | ✅ | ✅ | ✅ | ✅ | ✅ |
| Codex CLI | ❌ | ❌ | ❌ | ✅ | ⚠️ partial |
| Copilot CLI | ❌ | ✅ | ❌ | ✅ | ✅ |
| Kilo Code | ❌ | ❌ | ❌ | ❌ | none |
| Generic | ❌ | ❌ | ❌ | ❌ | manual |

## Wiki documentation system

Per-repo wiki: `features.md`, `architecture.md`, `codebase.md`, `.features` JSON.
`.wiki/` at root is the development instance; `bundle/repo-template/.wiki/` is the canonical shipped version.

## Install

```powershell
pwsh ./scripts/install.ps1 -For claude        # Claude Code
pwsh ./scripts/install.ps1 -For copilot       # GitHub Copilot CLI
pwsh ./scripts/install.ps1 -For opencode       # OpenCode
pwsh ./scripts/install.ps1 -For codex          # Codex CLI
pwsh ./scripts/install.ps1 -For all           # Everything
```

Verify with `pwsh ./scripts/validate-bundle.ps1` (0 errors, 0 warnings expected).