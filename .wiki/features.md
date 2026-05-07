# Caspar Bannink Agentic Coding Kit -- Features

User-visible capabilities of the kit. Update this file (and `.wiki/.features`)
whenever a slash command, sub-agent, tool, adapter, validator, install flag,
or lifecycle hook is added, removed, or materially changed. Surgical edits
only -- never rewrite.

## Workflow slash commands (9)

Auto-mounted at `~/.claude/commands/` and `~/.config/opencode/commands/`.
Each workflow wrapper now explicitly points back to the matching installed
`SKILL.md`, so Claude Code and OpenCode treat `/build`, `/review`, `/analyze`,
`/investigate`, `/plan`, `/refactor`, `/redesign`, and `/security-review` as
skill-backed workflow entrypoints rather than freeform chat prompts.
The Claude/OpenCode command wrappers now come from a single shared installer-
rendered template set instead of duplicated per-adapter markdown trees.

| Command | Purpose |
|---|---|
| `/bootstrap-harness` | Single high-level repo-init workflow: scaffold the repo, run archaeology, initialize `.kit`, and initialize `.wiki` |
| `/plan` | Clarify scope, map files, trace blast radius, stop for approval |
| `/build` | Execute approved plan: implement → review → verify gates |
| `/review` | Hierarchical code review (surface → interactions → synthesis → adversarial → false-positive verifier) |
| `/analyze` | Multi-angle research / synthesis |
| `/investigate` | Hypothesis-driven root-cause debugging |
| `/refactor` | Principle-driven restructuring with consequence tracing |
| `/redesign` | Greenfield UI / multi-component visual rebuild (swarm-eligible) |
| `/security-review` | Adversarial audit by attack class (swarm-eligible) |

## Sub-agents (15)

Auto-mounted at `~/.claude/agents/` and `~/.config/opencode/agents/`.
Available as `subagent_type` for the Task tool.
The five `workflow-*` transport agents for Claude Code and OpenCode are also
installed from shared templates; host-specific expert/reviewer agents remain in
their adapter directories because their frontmatter differs by host.

| Agent | Role |
|---|---|
| `workflow-explorer` | Cheap build-context explorer transport agent for Claude Code and OpenCode (`haiku`). |
| `workflow-implementer` | Main delegated build implementer transport agent for Claude Code and OpenCode (`sonnet`). |
| `workflow-reviewer` | Structured delegated reviewer transport agent for Claude Code and OpenCode (`sonnet`, read-only). |
| `workflow-skeptic` | Adversarial delegated skeptic transport agent for Claude Code and OpenCode (`sonnet`, read-only). |
| `workflow-ui-qa` | Delegated UI/behavior QA transport agent for Claude Code and OpenCode (`sonnet`, read-only). |
| `ux-driver` | Screenshot-based UX critic — structure, hierarchy, flow, a11y. Runs first in design loops. |
| `ui-driver` | Screenshot-based UI critic — typography, color, spacing, slop. Runs after ux-driver. |
| `playwright-navigator` | Discovers route + auth + selectors for unmapped screens. |
| `spec-reviewer` | Verifies implementation matches the agreed plan. |
| `code-quality-reviewer` | Maintainability, correctness, conventions, test quality, observability. |
| `modularity-expert` | Anti-slop architecture review — reuse-first, new-file justification, no pass-through wrappers. |
| `security-reviewer` | Trust boundaries, injection, auth mistakes, data leaks. |
| `adversarial-reviewer` | Final adversarial pass — production failure modes, regressions. |
| `final-verifier` | Iron Law gate — blocks completion without fresh verification evidence. |
| `qa-reviewer` | Browser / user-flow QA for UI or behavior-heavy changes. |

## Skills (28)

Auto-discovered at `~/.claude/skills/<name>/SKILL.md` and `~/.config/opencode/skills/<name>/SKILL.md`.

Workflow skills: `analyze`, `bootstrap-harness`, `build`, `plan`, `review`,
`investigate`, `refactor`, `redesign`, `security-review`.

Specialized skills: `ux-driver`, `ui-driver`, `playwright-navigator`,
`playwright-explorer`, `design-driver`, `aesthetic-director`, `swarm`, `tdd`,
`verification-loop`, `reflect`, `spec`, `consequence`, `git-archaeology`,
`derive-repo-skills`, `experts/modularity`, `experts/performance`,
`experts/silent-failure-hunter`, `experts/ui-ux`.

GStack-derived: `gstack-investigate`, `gstack-office-hours`,
`gstack-plan-eng-review`, `gstack-qa`, `gstack-review`.

## Repo initialization and retrieval

- `/bootstrap-harness` is now the single high-level repo-init command: scaffold
  first, then run `git-archaeology`, `kit-init`, and `wiki-init` so the repo is
  actually ready for coding.
- `/kit-init` now uses current code plus `git-archaeology` evidence to seed
  durable repo memory and repo-specific implementation conventions.
- `/wiki-init` now treats `.wiki/architecture.md` and `.wiki/codebase.md` as
  first-class cross-cutting docs, alongside `.wiki/index.md` and feature files.
- `wiki-resolver.ps1` now always loads `index.md`, `architecture.md`, and
  `codebase.md` when present, so those docs are actually consumed during
  coding/review workflows instead of sitting idle.

## Tools (30 PowerShell + 1 Python)

Live at `~/.agents/tools/` after install. Cross-platform (pwsh 7+ recommended,
PS 5.1 supported with BOM-prefixed scripts).

**Classification**: `scope-classifier.ps1`, `swarm-classifier.ps1`, `frontend-detector.ps1`.

**Lifecycle**: `pre-session.ps1`, `post-session.ps1`, `state-gate.ps1`,
`session-start-hook.ps1`, `session-end-hook.ps1`, `subagent-stop-hook.ps1`,
`precompact-hook.ps1`.

**Hook gates**: `pretool-bash-dispatcher.ps1`,
`pretool-read-delegation-gate.ps1`, `pretool-write-gateguard.ps1`,
`pretool-task-orchestrator-gate.ps1`, `posttool-bash-verify-mark.ps1`.

**Memory**: `specialist-memory-resolver.ps1`, `auto-consolidate.ps1`,
`compress-memory.ps1`.

**Edit/Test**: `edit-with-lint.ps1`, `test-loop.ps1`, `detect-slop.ps1`.

**Self-improvement**: `harness-propose.ps1`, `harness-review.ps1`,
`reflect-trigger.ps1`.

**Frontend**: `dev-server-runner.ps1`, `playwright-runner.ps1` (+ `.py`
backend), `visual-diff.ps1`, `design-fetcher.ps1`,
`bulk-fetch-inspiration.ps1`.

**Evidence**: `workflow-evidence.ps1`, `run-packet.ps1`, `handoff-register.ps1`.

**Setup helpers**: `merge-claude-settings.ps1`, `validate-repo-skills-index.ps1`,
`derive-repo-skills.ps1`, `scoped-derive-repo-skills.ps1`.

## Installers + validators

| Entry point | Purpose |
|---|---|
| `scripts/install.ps1` | Canonical installer (PowerShell, cross-platform via pwsh; renders shared workflow commands/agents into host-native dirs and replaces kit-managed globals including Copilot instructions) |
| `scripts/install.sh` | Thin Bash wrapper that delegates to `install.ps1` on Mac/Linux/WSL |
| `scripts/validate-bundle.ps1` | 5-check pre-flight (parse, encoding, paths, tools, adapters) |
| `scripts/doctor.ps1` | 17-check post-install health diagnostic |

**Install flags**:

- `-For <cli-list>` — install for specific CLIs (e.g., `claude`, `opencode`, `claude,opencode`, `all`)
- `-Auto` — detect CLIs on PATH and install for those
- `-BootstrapHarness` — one-command repo bootstrap: global assets + repo template + Claude/Copilot/generic repo adapters
- `-TargetRepo <path>` — per-repo install (writes `.kit/`, `.wiki/`, etc. into target)
- `-InstallRepoTemplate` — advanced partial install: drop only the repo template into target
- `-InstallAdapter <name|all>` — advanced partial install: install per-CLI adapter into target
- `-Upgrade` — backup `~/.agents/` before re-install
- `-Force` — overwrite existing files

## Adapters (6)

Per-CLI wiring at `bundle/adapters/<cli>/`.

| Adapter | Device-wide install | Per-repo install |
|---|---|---|
| `claude-code` | ✅ skills + agents + commands + hooks | ✅ |
| `opencode` | ✅ skills + agents + commands + plugin | ✅ |
| `codex-cli` | ✅ standalone reference + always-on rules | ✅ |
| `copilot-cli` | ✅ global `~/.copilot/copilot-instructions.md` | ✅ `.github/copilot-instructions.md` override + startup preflight for missing `.kit` / `.wiki` scaffold |
| `kilocode` | ❌ no native device-wide config | ✅ `.kilocode/rules/*.md` |
| `generic` | ✅ standalone reference + always-on rules in `~/AGENTS.md` | ✅ |

## Fresh verification enforcement

The harness treats verification evidence as stale after later edits. If files change after verification, verification must be rerun before completion can be claimed.

## Workflow enforcement

- SHARED / CRITICAL `/build` sessions now block delegated implementation and
  source-code edits until the same-session `plan.md` exists and
  `run-packet.json` records `approval_status=approved`.
- Claude Code and OpenCode now enforce a **two source-file read budget** before
  the first real build delegation. The third source-file read blocks until
  `workflow-explorer` or `workflow-implementer` is spawned.
- Multi-file source editing in a build session now blocks until a delegated
  `workflow-implementer` has been registered, so the top-level session cannot
  silently keep all non-trivial coding inline.

## Lifecycle automation

**Claude Code** — `~/.claude/settings.json` hooks merged on install:
- `SessionStart` → `pre-session.ps1`
- `SessionEnd` → `post-session.ps1`
- `SubagentStop` → `subagent-stop-hook.ps1`
- `PreCompact` → `precompact-hook.ps1`
- `PreToolUse(Read)` → `pretool-read-delegation-gate.ps1`
- `PreToolUse(Write/Edit)` → `pretool-write-gateguard.ps1`
- `PreToolUse(Task)` → `pretool-task-orchestrator-gate.ps1`
- `PostToolUse(Bash)` → `posttool-bash-verify-mark.ps1`

**OpenCode** — `~/.config/opencode/plugins/agentic-kit.ts`:
- `session.created` / `session.deleted` / `session.error` / `session.compacted`
- `tool.execute.before` routes Bash / Read / Write-Edit / Task to the same kit hooks
- normalizes file-path payloads and forwards the repo cwd so the shared PowerShell hooks can enforce write/read gates correctly
- `tool.execute.after` routes successful test commands to `posttool-bash-verify-mark.ps1`

**Task orchestration**:
- agent-cap enforcement now blocks before persisting over-cap agent registrations, rather than recording them and allowing the spawn anyway

**Codex / Copilot / Kilo / Generic** — manual lifecycle (agent calls
`pre-session.ps1` / `post-session.ps1` per the kit's instructions).

## Frontend visual loop

Auto-fires inside `/build` when `frontend-detector.ps1` returns
`visual_loop_recommended=true`.

Sequence: `dev-server-runner.ps1` (auto-start) → `playwright-navigator`
(if uncovered screen) → `playwright-runner.ps1` (capture) → `ux-driver`
(structure) → `ui-driver` (visual, only if structure_ok=true) →
`visual-diff.ps1` (regression check).

References: `~/.agents/context/design-references.md` (curated first-party
design system docs + abstracted patterns) + local cache at
`~/.agents/inspiration/` (populated by `bulk-fetch-inspiration.ps1`).

## Self-improvement loop (3 phases, auto-closes)

| Phase | Tool | Action |
|---|---|---|
| 1 | `auto-consolidate.ps1` | Mechanical dedup / archive / promote of reflection entries |
| 2 | `compress-memory.ps1` | Age out old session dirs + dedup memory.md |
| 2b | `harness-propose.ps1` | Detect 5+ recurring kit-level patterns; emit proposal (never auto-applies) |
| 3 | `reflect-trigger.ps1` | Gate next session if 5+ unaddressed reflections accumulate |

Manual review: `harness-review.ps1` lists pending proposals; user accepts /
rejects / defers each. Decisions persist in `~/.agents/proposals/decisions.jsonl`.

## Memory routing (4 buckets)

| Bucket | Target file | Use when |
|---|---|---|
| REPO-FACT | `.kit/context/memory.md` | Durable repo architecture, schema, verified commands |
| REPO-SPECIALIST | `.kit/context/agent-memory/{role}.md` | Repo-local guidance for one specialist role |
| SKILL-PATTERN | `~/.agents/skills/{skill}/memory.md` | Cross-repo workflow pattern with recurring evidence |
| SESSION-ONLY | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` | Task progress, scratch, session-private notes |

Specialist memory loads lazily via `specialist-memory-resolver.ps1` --
never auto-loaded at session start.

## Always-on global rules (installed to user's CLAUDE.md / prompt.md / AGENTS.md)

A 25-line block bracketed by `<!-- agentic-kit:include -->` markers,
covering:
1. `.wiki/features.md` mandate (this file's reason for existing)
2. Iron Law: no completion claims without fresh verification evidence
3. The kit's slash command list

The block is idempotent on re-install. Long-form details stay in the
standalone `agentic-kit.md` reference doc next to each CLI's config.

## Test surface

- `tests/Pester/harness.Tests.ps1` — load-bearing script smoke tests
- `.github/workflows/validate.yml` — CI runs `validate-bundle.ps1` + Pester on push and PR
- `benchmarks/quick-harness-check.ps1` — 3-task smoke test for end-to-end loops
- `benchmarks/mini-coding-eval.py` — 10-task pass/fail benchmark
