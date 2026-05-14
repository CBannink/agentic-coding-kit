# Caspar Bannink Agentic Coding Kit

A disciplined harness for **plan-first, multi-agent coding** that works the
same way under Claude Code, OpenCode, Kilo Code, Codex CLI, Copilot CLI, and
anything else that reads `AGENTS.md`.

It gives you:

- **Auto-classified scope and tier** — the system decides INLINE / TARGETED / FULL / SWARM per task; you don't pick.
- **Sequential by default, swarm by gate** — fan-out only fires when verb is parallel-safe + scope is fan-out-able + you opted in. No accidental swarms on focused work.
- **Self-improvement loop that closes itself** — the harness captures objective failures, mechanically deduplicates / archives / promotes them, and gates the next session if real backlog accumulates. Most cleanup needs no `/reflect` call.
- **4-axis memory model** — durable repo facts, role-specific repo memory, session-private handoffs, cross-repo skill patterns. Each routed via explicit rules.
- **Design + Playwright loop** — capture current UI state, fan out a `design-driver` agent per screen, apply changes, visual-diff before/after.
- **Validator + tests** — `validate-bundle.ps1` blocks broken kits at install; Pester suite covers the load-bearing scripts.

## Start here

- **Want the clearest install path?** Read [`docs/setup-and-install.md`](docs/setup-and-install.md).
- **Need to demo this to a team?** Use [`docs/team-demo-guide.md`](docs/team-demo-guide.md).
- **Need to verify or re-verify an install?** Run `pwsh ./scripts/doctor.ps1`.

## How it works (the 5-minute overview)

The kit is one shared brain (`~/.agents/`) that any AI coding CLI can talk to.
You install it once, point your CLI at it, and from then on every session
follows the same disciplined loop regardless of which CLI you're using.

```
┌─────────────────────────────────────────────────────────────────────┐
│  Your CLI (Claude Code / OpenCode / Codex / Copilot / Kilo / etc.) │
│         │                                                           │
│         │ reads ~/.<cli>/agentic-kit.md (companion file)           │
│         │ + include marker in CLAUDE.md / AGENTS.md / prompt.md    │
│         ▼                                                           │
│  ╔══════════════════════════════════════════════════════════════╗  │
│  ║  Shared brain: ~/.agents/                                    ║  │
│  ║  ├── skills/      34 cross-CLI skills (build/review/swarm…)  ║  │
│  ║  ├── tools/       47+ PS scripts (classifiers, gates, hooks) ║  │
│  ║  ├── workflows/   gstack / superpowers / caspar plugins      ║  │
│  ║  ├── context/     protocols, skill-memory-index              ║  │
│  ║  └── .kit/session-state/<id>/ per-session gates + handoffs   ║  │
│  ╚══════════════════════════════════════════════════════════════╝  │
│         ▲                            ▲                              │
│         │                            │                              │
│  Lifecycle hooks fire           Tools called inline                │
│  (Claude settings.json,         (state-gate, edit-with-lint,       │
│   OpenCode plugin,              test-loop, scope-classifier,       │
│   Copilot baked instructions)   pre/post-session, …)               │
└─────────────────────────────────────────────────────────────────────┘
```

### What happens in one session

1. **Pre-session** (auto via hook, or called by the agent at start of `/build`):
   `scope-classifier` reads changed files → returns `ISOLATED` / `SHARED` / `CRITICAL`.
   `pre-session.ps1` recommends a tier (`INLINE` / `TARGETED` / `FULL` / `SWARM`) and
   `swarm-classifier` decides if fan-out is allowed (verb parallel-safe + scope
   fan-out-able + opt-in). A BRIEF block is emitted listing scope, tier, swarm
   mode, and unaddressed reflections. The agent pastes/reads it.

2. **During work**, the agent marks gates as it progresses:
   `context_loaded` → `implementation_done` → `verification_evidence`.
   Edits go through `edit-with-lint.ps1` (refuses to write syntax-broken files).
   Tests go through `test-loop.ps1` (marks the verification gate on pass,
   detects 3 same-signature failures = `stuck` and forces escalation).

3. **Post-session** (auto via hook, or final step of `/build`):
   `post-session.ps1` checks all required gates fired. Failure detectors emit
   structured reflections. Then **auto-consolidate** runs mechanically — dedup,
   archive promoted patterns, drop stale single-occurrence entries, promote
   recurring additive patterns to the repo workflow file. Then **compress-memory**
   ages out old session dirs and dedups skill memory. Then **harness-propose**
   checks for kit-level patterns recurring 5+ times in 30 days and writes a
   proposal to `~/.agents/proposals/` (never auto-applies). Then **reflect-trigger**
   gates the next session if 5+ unaddressed reflections accumulate.

The result: most cleanup happens with zero human input. You only see the
self-improvement loop when something genuinely needs your judgment.

### The 4 axes that decide behavior

| Axis | Values | Decided by |
|---|---|---|
| **Scope** | ISOLATED / SHARED / CRITICAL | `scope-classifier.ps1` reading changed files |
| **Tier** | INLINE / TARGETED / FULL / SWARM | `pre-session.ps1` from scope + file count |
| **Mode** | sequential / swarm-review / swarm-fanout | `swarm-classifier.ps1` from verb + scope + opt-in |
| **Memory** | REPO-FACT / REPO-SPECIALIST / SKILL-PATTERN / SESSION-ONLY | Explicit routing rules in writeback protocol |

You don't pick these. The harness picks them and the BRIEF block tells you
what it picked. You can override, but the default is the right answer.

### Why one shared brain across CLIs

Every CLI has its own config conventions (`CLAUDE.md`, `AGENTS.md`, `prompt.md`,
`~/.copilot/copilot-instructions.md`, `.kilocode/rules/`). Rather than fork the
kit per CLI, the kit's logic lives in `~/.agents/` once, and a thin **adapter**
per CLI writes the right global or repo-local instructions for that host.
Switch CLIs at any time — the workflows, gates, memory, and self-improvement
loop are identical.

## Requirements

- **PowerShell 7+ (`pwsh`) recommended** — the runtime tools are designed for pwsh. Windows PowerShell 5.1 still works for most flows, but it is a compatibility path, not the preferred one. Install pwsh via `winget install Microsoft.PowerShell` or https://aka.ms/PSWindows.
- **Python 3.10+** with `playwright` + `pyyaml` — only if you use `/redesign` or `playwright-explorer`. Skip if you don't need UI screenshot capture.
  ```
  pip install playwright pyyaml && python -m playwright install chromium
  ```
- **Mac/Linux**: `pwsh` works natively. Use `scripts/install.sh` if you prefer bash for the installer step itself.

## Install

### Quick start — machine install

If you want the shortest step-by-step path instead of the full reference below,
start with [`docs/setup-and-install.md`](docs/setup-and-install.md).

```powershell
# Use Claude Code
pwsh ./scripts/install.ps1 -For claude

# Use GitHub Copilot CLI / Chat
pwsh ./scripts/install.ps1 -For copilot

# Use OpenCode
pwsh ./scripts/install.ps1 -For opencode

# Use Codex CLI
pwsh ./scripts/install.ps1 -For codex

# Use multiple
pwsh ./scripts/install.ps1 -For "claude,opencode"

# Or install for every CLI that has a meaningful device-wide config
# (Claude, Codex, Copilot, OpenCode, plus a generic ~/AGENTS.md for Aider/Cline/Cursor/etc.)
pwsh ./scripts/install.ps1 -For all

# Or auto-detect what's on your PATH and install for those
pwsh ./scripts/install.ps1 -Auto
```

Each `-For <cli>` does three things:

1. **Populates `~/.agents/`** with skills, tools, protocols, and the workflow plugins skills reference (gstack / superpowers / caspar-workflows). Renders `skill-memory-index.json` with absolute paths.
2. **Writes the kit instructions companion** to that CLI's config dir (e.g. `~/.claude/agentic-kit.md`, `~/.copilot/agentic-kit.md`, `~/.config/opencode/agentic-kit.md`, `~/.codex/agentic-kit.md`, or `~/.agentic-kit/AGENTS.md` for the generic case).
3. **Wires lifecycle automation** — for Claude Code merges hooks into `~/.claude/settings.json`; for OpenCode installs the plugin at `~/.config/opencode/plugins/agentic-kit.ts`; for Copilot installs the workflow instructions globally at `~/.copilot/copilot-instructions.md` (with repo-level `.github/copilot-instructions.md` remaining an optional override).

Re-running the installer replaces the kit-managed global assets under `~/.agents/` and rewrites the global Copilot instructions from the current kit source, so old generations do not accumulate in the active install. User-owned runtime state and accumulated skill memory are preserved across normal reinstalls.

### One-command repo bootstrap

If you want a repo fully wired for the harness in one go — `.kit/`, `.wiki/`, `AGENTS.md`, `CLAUDE.md`, and `.github/copilot-instructions.md` — use:

```powershell
pwsh ./scripts/install.ps1 -BootstrapHarness -TargetRepo C:\path\to\repo
```

That one command:

1. refreshes `~/.agents/`
2. installs device-wide rules for Claude, Copilot, and generic `AGENTS.md`
3. drops the repo template into the target repo
4. installs the repo adapters for Claude, Copilot, and generic agents
5. seeds the cross-cutting wiki stubs `architecture.md` and `codebase.md`

When the host supports repo slash commands, the preferred setup command to suggest is:

```text
/bootstrap-harness
```

That command should resolve to the shell bootstrap path above AND then continue
through the evidence-based init flow:

```text
/bootstrap-harness
  -> install.ps1 -BootstrapHarness
  -> /git-archaeology   (when enough history exists)
  -> /kit-init
  -> /wiki-init
```

So `/bootstrap-harness` is the single high-level repo-init path, not just a
thin shell alias.

Use the older `-InstallRepoTemplate` / `-InstallAdapter` flags only for advanced partial installs.

### Setup when your repo already has rules / pipeline

Most real repos already have:
- A repo `CLAUDE.md` / `AGENTS.md` with project conventions, build commands, agent personas
- Project-scoped `.claude/agents/`, `.claude/commands/`, `.claude/skills/`, `.claude/settings.json`
- A custom pipeline (`hand_off.md`, `agents/handoffs/`, `memory/MEMORY.md`, `agents/session_state.md` from gstack-style or your own)
- Other-CLI configs (`.cursor/rules/`, `.aider.conf.yml`, `.github/copilot-instructions.md`, `.kilocode/rules/`)

The kit was designed to coexist with these. **Two-step install for an existing-rules repo**:

```powershell
# 1. Global install (one time, device-wide)
pwsh ./scripts/install.ps1 -For all       # or -For "claude,opencode,codex"

# 2. In the repo, run /kit-migrate (one time, per repo)
#    Open Claude Code or OpenCode in your repo and type:
#    /kit-migrate
```

`/kit-migrate` is a **convergence operation**: it scans your repo for legacy
agentic conventions and brings the *structural* ones (handoff path, memory
routing, session state, lifecycle bookkeeping) into alignment with the
kit's pattern, while *preserving* domain preferences (build/test commands,
code style, agent personas, project-scoped `.claude/agents/`, custom
skills, deploy gates).

`/kit-init`, `/wiki-init`, and `/git-archaeology` remain the lower-level
building blocks underneath `/bootstrap-harness`, but normal setup guidance
should point to the single high-level command.

**Litmus test for what converges vs what stays**:
- Rule about *where state goes / how session is bookkept / how memory routes* → **STRUCTURAL**, converges to kit pattern
- Rule about *what gets built / how it's tested / who reviews / project identity* → **PREFERENCE**, stays untouched

`/kit-migrate` shows you a diff of every proposed change to your `CLAUDE.md`
and asks before applying. Default = ask. Never auto-applies destructive moves.

If a repo has `.openclaw/` / `.vibe/` / other CLI-native trees the kit
doesn't know about, those are KEPT — repo wins on those by default.

### Per-CLI enforcement matrix

| CLI | Slash commands | Sub-agents | Skills auto-discover | PreToolUse hooks | PostToolUse hooks | Lifecycle hooks |
|---|---|---|---|---|---|---|
| **Claude Code** | ✅ `~/.claude/commands/` | ✅ `~/.claude/agents/` | ✅ | ✅ via `settings.json` | ✅ | ✅ |
| **Codex CLI** | ❌ no native discovery | ❌ | ❌ | ✅ via `~/.codex/config.toml` (Bash/apply_patch/MCP only — issue #20204) | ✅ | ⚠️ partial |
| **OpenCode** | ✅ `~/.config/opencode/commands/` | ✅ `~/.config/opencode/agents/` | ✅ | ✅ via plugin `tool.execute.before` | ✅ | ✅ via plugin events |
| **Copilot CLI** | ❌ (issue #1113) | ✅ `~/.copilot/agents/` + `<repo>/.github/agents/` (`.agent.md`, since v0.0.396) | ❌ no documented surface | ✅ via `<repo>/.github/hooks/preToolUse.json` (since v0.0.397) | ✅ same | ✅ `sessionStart`, `sessionEnd`, `subagentStop`, etc. (repo scope only — no documented user-level hooks dir) |
| **Kilo Code** | ❌ (modes, not commands) | ❌ | ❌ | ❌ | ❌ | none |
| **Generic** (Aider/Cline/etc.) | ❌ | ❌ | ❌ | ❌ | ❌ | manual |

### Which CLI should you use?

Honest take as of late 2026:

- **Claude Code** — most mature hook ecosystem, broadest tool coverage (every tool fires hooks), supports `additionalContext` injection via SessionStart hook, full skills/agents/commands auto-discovery. Best fit if you want the kit's full enforcement surface working with the least wiring.
- **Codex CLI** — hooks now structurally near-identical to Claude (TOML config is cleaner than Claude's settings.json sprawl), `PermissionRequest` as a distinct event is more granular, but: hooks fire only on Bash/apply_patch/MCP (not list_dir/plan/web_search per issue #20204), and no native slash command / sub-agent / skill discovery. Strong if you want the hook-layer enforcement and don't need the discovery surfaces.
- **OpenCode** — has events but they were event-only until recently; the kit now wires `tool.execute.before` / `.after` to fire the same hook scripts as Claude, but the kernel-level "block before exec" contract isn't quite as battle-tested as Claude or Codex. Solid choice if you prefer it for other reasons.

For an opinionated kit like this, **Claude Code is the safest default**;
**Codex CLI is a strong alternative if you prefer its TOML config and
PermissionRequest model**; **OpenCode is fine for general use**. The kit
ships adapters for all three so you can switch any time without
re-installing.

**A note on `copilot` and `kilocode`:** Copilot now has a useful device-wide
install path at `~/.copilot/copilot-instructions.md`, which the kit rewrites
from the current adapter source on each install so stale generations do not
accumulate. Repo-level `.github/copilot-instructions.md` remains an optional
override, and the per-repo Copilot adapter also installs `.github/agents/`,
`.github/hooks/`, plus shell workflow wrappers at `~/.agents/bin/copilot/`.
User-defined slash commands are still unsupported there, so invoke workflows
via those shell wrappers or direct `gh copilot --agent ...` / `copilot --agent ...`
calls. The shell wrappers auto-detect either CLI entrypoint and stream live
phase / spawned-agent updates to stderr plus `progress.log` in the session dir.
Kilo Code
still reads `.kilocode/rules/*.md` from each workspace, so it remains repo-local.

Pre-flight runs `validate-bundle.ps1` and refuses to install a broken kit (override with `-Force`).

After install, restart your CLI. Verify with:

```powershell
pwsh ./scripts/doctor.ps1   # health report
```

### Per-repo bootstrap (advanced / partial installs only)

If you want the kit's repo-template (`.kit/context/`, `.kit/workflows/`, `.wiki/`) dropped into a specific repo:

```powershell
pwsh ./scripts/install.ps1 -BootstrapHarness -TargetRepo C:\path\to\repo
```

### Upgrade safely

```powershell
pwsh ./scripts/install.ps1 -Upgrade -For all
```

The `-Upgrade` flag moves your existing `~/.agents/` to a timestamped backup before overwriting. Hand-merge any customizations afterward.

## Adapter matrix — what auto-fires per CLI

| Adapter | Surface | Lifecycle automation |
|---|---|---|
| **Claude Code** | `CLAUDE.md` + `.claude/commands/*.md` (8 commands) | ✅ `~/.claude/settings.json` hooks fire `pre-session` / `post-session` / `subagent-stop` / `pre-compact` automatically |
| **OpenCode** | `prompt.md` + `~/.config/opencode/plugins/agentic-kit.ts` | ✅ TypeScript plugin wires `session.created` / `session.deleted` / `session.idle` / `session.compacted` |
| **Copilot CLI** | `~/.copilot/copilot-instructions.md` (+ optional repo override at `.github/copilot-instructions.md`) plus inherited skills from `~/.agents/skills/` on current builds | ✅ Lifecycle baked into instructions, plus repo-scoped `.github/hooks/*.json`; on current builds the inherited `/goal` / `/build` / `/investigate` / `/review`-style skills stay inline in the main Copilot session and only spawn leaf agents; `~/.agents/bin/copilot/kit-*.sh` and direct `gh copilot --agent ...` remain explicit fallback entrypoints |
| **Codex CLI** | `AGENTS.md` | Manual — Codex hook surface varies by version, no fabricated config shipped |
| **Kilo Code** | `AGENTS.md` + `.kilocode/rules/*.md` (5 modes) | Manual or via VSCode tasks.json |
| **Generic** | `AGENTS.md` (canonical for Aider, Cline, Cursor, Continue, etc.) | Manual |

### Copilot CLI entrypoints

 Copilot's built-in slash commands are not replaceable. On current Copilot CLI
 builds, `pwsh ./scripts/install.ps1 -For copilot` also exposes the kit's
 inherited workflow skills from `~/.agents/skills/`, so `/goal`, `/build`,
 `/investigate`, `/analyze`, and the `gstack-*` skills can appear directly in
 `/skills` and run inline in the main Copilot session. The explicit fallback
 entrypoints remain:

- POSIX: `bash ~/.agents/bin/copilot/kit-{analyze,build,goal,investigate,plan,refactor,redesign,review,security-review}.sh "<prompt>"`
- Windows: `pwsh ~/.agents/bin/copilot/kit-build.ps1 "<prompt>"` (matching `.ps1` shims exist for the same wrapper set)
- `gh copilot --agent goal-orchestrator -p "Achieve this autonomously: <goal>"` (or `copilot --agent ...` if the standalone binary is installed)
- `gh copilot --agent pr-reviewer -p "Review the current PR in this repo."`

If you also run `pwsh ./scripts/install.ps1 -TargetRepo <path> -InstallAdapter copilot`,
the repo-scoped `.github/agents/` and `.github/hooks/` surfaces are installed too.

## Core operating model

### Slash commands (workflows the user types)

| Command | What it does | Swarm? |
|---|---|---|
| `/bootstrap-harness` | **Goal-conditioned** repo init. Detects git workflow + architecture + PR conventions before scaffolding. Iterates until every required outcome exists. Writes `.kit/context/conventions.md` so other agents follow YOUR style. | sequential w/ light parallel evidence |
| `/plan` | clarify scope, map files, trace blast radius, stop for approval | sequential |
| `/build` | implement → review → verify pipeline. Main session orchestrates; spawns workflow agents + specialists via Task tool per phase. | sequential (parallel-reviewers OK at FULL tier) |
| `/review` | hierarchical: surface → interactions → synthesis → adversarial → false-positive verifier | sequential, optional `swarm-review` |
| `/analyze` | multi-angle research/synthesis | sequential |
| `/investigate` | hypothesis-driven root-cause debugging | sequential |
| `/refactor` | principle-driven restructuring with consequence tracing | sequential |
| `/redesign` | greenfield UI / multi-component visual rebuild | **swarm-eligible** — fan out one `design-driver` per screen |
| `/security-review` | adversarial audit by attack class | **swarm-eligible** — fan out one agent per attack class |

### Agent inventory (full kit, 17 agents per host)

These are the leaf agents the slash commands spawn via the Task tool. Each is a separate sub-context with its own description-matched routing trigger.

#### Workflow agents (5) — generic transport layer

| Agent | Purpose |
|---|---|
| `workflow-explorer` | Cheap exploration, file discovery, code search, contract tracing |
| `workflow-implementer` | Any code change beyond a one-line mechanical edit |
| `workflow-reviewer` | Scoped diff review without polluting the orchestrator's context |
| `workflow-skeptic` | Pressure-test plans / diffs for hidden regressions |
| `workflow-ui-qa` | Task-flow / defaults-parity / artifact-safety QA on UI |

#### Specialist agents (10) — domain-expert deep dives

| Agent | Focus |
|---|---|
| `code-quality-reviewer` | Correctness, tests, observability, conventions |
| `security-reviewer` | Auth, injection, secrets, OWASP Top 10 |
| `modularity-expert` | Architecture, DI, abstractions, file placement |
| `adversarial-reviewer` | Production failure modes, edge cases, race conditions |
| `final-verifier` | Iron Law gate: fresh test/build/lint exit-0 evidence |
| `qa-reviewer` | User-flow / regression QA on UI changes |
| `spec-reviewer` | Verify implementation matches the agreed plan, no scope drift |
| `playwright-navigator` | Discover Playwright route + auth + selectors for new screens |
| `ux-driver` | UI structural critique — info architecture, hierarchy, density, a11y |
| `ui-driver` | Visual polish — typography, color, spacing, AI-slop detection |

#### Orchestrators (2) — special-purpose composition

| Agent | Purpose |
|---|---|
| `goal-orchestrator` | **Autonomous goal-achievement loop.** Classifies goal type (CODE / DESIGN / INVESTIGATION / REFACTOR / MULTI), picks the right toolchain, runs a convergence loop (cap 6 iterations) with mechanical stuck detection, rollback gate, empty-diff watchdog. Includes a full DESIGN pipeline (aesthetic-director → playwright-navigator → playwright-runner → ux-driver → ui-driver → visual-diff). Applies dynamic model selection (scope-aware + trust-aware via `model-selector.ps1` + `agent-trust-scorer.ps1`), lateral-drift detection (goal divergence across iterations), rollback-oscillation detection (same rollback triggered twice = escalate), and cross-provider ensemble routing on Copilot CLI for output diversity. |
| `pr-reviewer` | **NEW.** Holistic human-style PR review. Reads PR title + description + commits + diff + CI + repo conventions; outputs a PR-comment-style review with `APPROVE` / `REQUEST_CHANGES` / `COMMENT` verdict. Distinct from `code-quality-reviewer` (lint-class diff review) — `pr-reviewer` is the verdict-issuing senior-engineer pass. |

### Highlight: `pr-reviewer` (NEW in 2026-05)

A dedicated PR review agent that mimics what real senior engineers actually check:

```text
# Claude Code / OpenCode
Use the pr-reviewer agent to review this PR.

# Copilot CLI
gh copilot --agent pr-reviewer -p "Review the current PR in this repo."
```

The agent will:

1. **Read holistically** — title, description, commits, full diff, CI status, `.kit/context/conventions.md` (the conventions file the bootstrap detected for your repo, so the review is style-aware not generic).
2. **Scope check first** — if the PR description doesn't match the diff, it surfaces that before line-by-line review (a PR doing two things is two PRs).
3. **Walk the 10-dimension human-reviewer checklist** — correctness, tests, scope-match, architecture/convention adherence, security (when surface fits), performance (when surface fits), backwards compat, error handling/observability, style/naming, documentation, PR hygiene, risk profile.
4. **Synthesize** as a Markdown PR comment: Overall verdict, Blocking, Non-blocking, Nits, Praise, Suggested follow-ups.

First line is machine-parseable for CI integration:
```
PR_REVIEW: APPROVE | files: 7 | additions: +312 | deletions: -45
```

Sources cited in the agent body: Google's [Code Review Developer Guide](https://google.github.io/eng-practices/review/reviewer/), [Conventional Comments](https://conventionalcomments.org/) for the BLOCKING/NON-BLOCKING/NIT taxonomy, plus Anthropic's engineering review patterns.

### Autonomy: 3-axis classification

The system chooses behavior automatically:

```
Scope:  ISOLATED  /  SHARED  /  CRITICAL          (how dangerous?)
Tier:   INLINE  /  TARGETED  /  FULL  /  SWARM    (how much ceremony?)
Mode:   sequential  /  swarm-review  /  swarm-fanout  (how to execute?)
```

`scope-classifier.ps1` picks scope from changed files. `pre-session.ps1` recommends a tier from scope + file count. `swarm-classifier.ps1` decides mode from verb + scope + opt-in.

### Dynamic model selection

The kit right-sizes model cost without manual intervention:

- **`model-selector.ps1`** takes `-Scope` (ISOLATED / SHARED / CRITICAL) and `-Role` (e.g. `code-quality-reviewer`) and returns a JSON object with `model`, `tier`, and `provider`. Maps scope+role to fast/balanced/premium tiers — exploration and low-risk review get haiku/mini, implementation and security review get sonnet, final-verifier and goal-orchestrator get opus/premium.
- **`agent-trust-scorer.ps1`** tracks per-agent reliability from session history. Agents that emit repeated false-positives, skip verification, or trigger stuck-detection get their tier downgraded and receive a calibration prompt injected by the orchestrator on next spawn.
- **Cross-provider ensemble on Copilot CLI** — when the active CLI is Copilot, `model-selector.ps1` can return a secondary provider (e.g. OpenAI GPT for one reviewer, Anthropic Claude for another) to reduce correlated blind spots in swarm-review mode.
- **Configurable overrides**: set `MODEL_FAST`, `MODEL_BALANCED`, `MODEL_PREMIUM` env vars to pin specific model IDs, or point `MODEL_MAP_FILE` at a JSON file for a full scope×role matrix.

```powershell
# Typical usage before spawning a subagent:
$ pwsh ~/.agents/tools/model-selector.ps1 -Scope SHARED -Role code-quality-reviewer
  {"model":"claude-sonnet-4-6","tier":"balanced","provider":"anthropic","trust_adjusted":false}
```

### When swarms fire (gating function)

All three must hold:

1. **Verb is parallel-safe** — `audit`, `explore`, `port`, `redesign`, `pentest`, `security-review`, `bulk-migrate`, `brainstorm`, etc. Not `fix`, `implement`, `ship`, `migrate-schema`.
2. **Scope is fan-out-able** — `ISOLATED` with ≥4 changed files, OR ≥8 files with parallel-safe verb. `CRITICAL` scope **never** swarms (single-writer discipline).
3. **You opted in** — `$env:AGENTS_SWARM = "1"` OR task contains "swarm" OR you invoke `/redesign` or `/security-review` directly.

If only condition #1 is met, classifier returns `swarm-review` instead of `swarm-fanout` — sequential implementer + N concurrent reviewers. This is the right default for polish-quality work on focused features.

### Swarm details

When `mode = swarm-fanout`:

```
1. Decompose into independent items (one per screen / module / attack class / perspective)
2. For each item: spawn one fresh-context agent
   pwsh ~/.agents/tools/state-gate.ps1 -SessionId <id> -AddAgent <name> -EnforceAgentCap
   (cap = 24 at SWARM tier)
3. One synthesizer agent merges all N outputs (sequential, surfaces conflicts)
4. One verifier agent confirms internal consistency
5. workflow-evidence.ps1 records tier=SWARM with reason
```

Bad decomposition kills swarms. The skill at `~/.agents/skills/swarm/SKILL.md` documents the failure modes.

### Memory routing — 4 buckets, explicit rules

| Bucket | Target | Use when |
|---|---|---|
| `REPO-FACT` | `.kit/context/memory.md` | Durable repo architecture, schema, verified commands, constraints |
| `REPO-SPECIALIST` | `.kit/context/agent-memory/{role}.md` or `shared.md` | Repo-local guidance only useful to one specialist role |
| `SKILL-PATTERN` | `~/.agents/skills/{skill}/memory.md` | Cross-repo workflow pattern with recurring evidence |
| `SESSION-ONLY` | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` (default `.kit/session-state/{id}/handoffs.md` in a bootstrapped repo, else `~/.agents/session-state/{id}/handoffs.md`) | Task progress, scratch, session-private notes |

Copilot's own host-native runtime folders (for example `~/.copilot/session-state/`)
remain host-managed. The repo-local move applies only to kit-managed artifacts.

`SKILL-PATTERN` is intentionally cross-repo, but it should stay narrow: only
workflow patterns that are genuinely reusable in a different repository belong
there. Repo-specific build knowledge stays in `.kit/context/memory.md` or
`.kit/context/agent-memory/`.

Specialist memory is **lazy-loaded via mechanical resolver**:

```
pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId <id> -Role <role> -RepoRoot <repo>
```

If `found=true`, embed the returned `prompt_block` directly in the spawned subagent prompt. Never auto-load the directory at session start.

### Self-improvement loop (3 phases, auto-closes)

The kit captures objective failures, surfaces them, consolidates them mechanically, and proposes harness-level changes when patterns recur — all without auto-applying anything risky:

```
post-session writes failures (11 detectors fire on objective conditions)
   |
   ├─ tier overridden downward          ├─ trivial verification command
   ├─ false-positive verifier skipped   ├─ verification gate marked, no commands
   ├─ workflow-evidence missing fields  ├─ bloated handoff summary
   ├─ agent cap exceeded                ├─ agent state mismatch
   ├─ required gates incomplete         ├─ repeated task across sessions
   └─ long session (>8h)
        |
PHASE 1 ─ auto-consolidate (mechanical, REPO-level)
   ├─ DEDUP   — merge identical {class, pattern}
   ├─ ARCHIVE — drop entries already in memory.md as Promoted:
   ├─ STALE   — drop single-occurrence entries >30 days
   └─ PROMOTE — additive patterns with count≥2 → repo workflow file (with marker)
        |
PHASE 2 ─ compress-memory (slop prevention)
   ├─ Archive session-state dirs >60 days
   ├─ Age out history.md entries >90 days → history.archive.md
   ├─ Dedup memory.md sections (whitespace-normalized keys)
   ├─ Dedup skill memory files
   └─ Soft-limit warnings (memory>300 lines, skill>200 lines)
        |
PHASE 2b ─ harness-propose (KIT-level meta-pattern, never auto-applies)
   ├─ Detect patterns with 5+ total AND 3+ in last 30 days AND kit-level keyword
   ├─ Write proposal markdown to ~/.agents/proposals/<id>.md
   ├─ Show prominent yellow banner with review commands
   └─ Human reads + decides via harness-review.ps1; implementation stays manual
        |
PHASE 3 ─ reflect-trigger (gate)
   ├─ <3 unaddressed: silent
   ├─ 3-4: soft warning at next pre-session
   └─ 5+: mandatory /reflect before next session ships
```

Most sessions never need a manual `/reflect` call — the mechanical pass keeps the backlog clean. `/reflect` (the skill) is reserved for `class=gating` / `class=routing` / `class=verification` patterns that need judgment.

### Meta-pattern — harness proposals (the kit's research bet)

When the same kit-level failure pattern recurs **5+ total times AND 3+ within the last 30 days AND matches kit vocabulary** (e.g., "tier overridden downward", "false-positive verifier skipped"), `harness-propose.ps1` writes a markdown proposal describing the recurring problem, suggested target files (`state-init.ps1`, `scope-classifier.ps1`, etc.), evidence, and risks. **It never auto-applies.**

```
# List pending proposals (run any time, or wait for post-session banner)
pwsh ~/.agents/tools/harness-review.ps1

# Read full proposal body
pwsh ~/.agents/tools/harness-review.ps1 -Show <proposal-id>

# Decide (and implement manually if accepted)
pwsh ~/.agents/tools/harness-review.ps1 -ProposalId <id> -Action accept|reject|defer -Note "..."
```

Decisions persist in `~/.agents/proposals/decisions.jsonl`. Rejected/accepted patterns won't re-emit. The implementation gap is intentional — the kit detects and proposes, the human decides and implements. No public production harness has this combination.

### Edit linting (SOTA enforcement pattern)

`edit-with-lint.ps1` applies a single file edit with linter validation. Refuses to commit changes that don't pass the file's syntax check — catches errors at the tool layer before they hit the test loop. Auto-detects linter by extension (Python, TS/JS via `node --check`, Go via `gofmt`, shell via `bash -n`). Atomic write + revert on lint fail. Pattern from SWE-agent (single most-cited specific enforcement mechanism in the literature).

```
# Apply edit; refuse if it breaks syntax or Find is ambiguous
pwsh ~/.agents/tools/edit-with-lint.ps1 -Path src/auth.ts -Find "old code" -Replace "new code"

# Replace all occurrences (override unique-match guard)
pwsh ~/.agents/tools/edit-with-lint.ps1 -Path src/auth.ts -Find "x" -Replace "y" -All
```

### Test-loop heartbeat

`test-loop.ps1` runs the project's test command, captures structured output, marks the verification_evidence gate on pass, and detects loops (3 same-signature failures = `status: stuck`, exit 3, escalation message). Pulls verification discipline from "agent must remember" to "harness enforces."

```
pwsh ~/.agents/tools/test-loop.ps1 -SessionId <id> -Command "npm test"
pwsh ~/.agents/tools/test-loop.ps1 -SessionId <id> -Command "pytest -x" -PassOnExitCode 0,1
```

### Slop detection

`detect-slop.ps1` scans for AI-slop patterns: comment-bloat, commented-out code, empty try/catch, oversized files/functions, deep nesting, generic var names, trailing whitespace. Reports findings; `-Fix` only applies safe cosmetic fixes (whitespace + blank line collapsing).

```
pwsh ~/.agents/tools/detect-slop.ps1 -Path src/                 # report only
pwsh ~/.agents/tools/detect-slop.ps1 -Path src/ -Fix            # also strip trailing whitespace, collapse triple+ blank lines
pwsh ~/.agents/tools/detect-slop.ps1 -Json                      # machine-readable
```

## Repository layout

| Path | Purpose |
|---|---|
| `bundle/global/.agents/skills/` | 24 cross-repo skills (build, review, analyze, swarm, redesign, security-review, design-driver, playwright-explorer, etc.) |
| `bundle/global/.agents/tools/` | 47+ PowerShell tools + 1 Python — classifiers, hooks, resolvers, runner, validator, **test-loop, edit-with-lint, detect-slop, compress-memory, harness-propose, harness-review, auto-consolidate, reflect-trigger, model-selector, agent-trust-scorer, reflection-emitter-stats** |
| `bundle/global/.agents/context/` | Protocol files (writeback, reflection, repo-specialist-memory, workflow-evidence) + skill-memory-index template |
| `bundle/global/.agents/workflows/` | gstack + superpowers + caspar-workflows plugin trees (referenced by skills regardless of which CLI you use) |
| `bundle/repo-template/` | What gets dropped into each target repo (`.kit/context/`, `.kit/workflows/`, `.kit/skills/`, `.wiki/`, `.agents/screen-flows.yaml`) |
| `bundle/adapters/{claude-code,codex-cli,copilot-cli,opencode,kilocode,generic}/` | Per-CLI instruction files + lifecycle wiring |
| `bundle/adapters/_shared/` | Canonical instruction body referenced by all adapters |
| `scripts/install.ps1` | Installer with adapter selection + template rendering + pre-flight validation |
| `scripts/install.sh` | Bash counterpart for Mac/Linux/WSL |
| `scripts/validate-bundle.ps1` | 5-check self-validator (parse, encoding, paths, tools, adapters) |
| `tests/Pester/` | Smoke tests for the load-bearing scripts |
| `docs/` | Architecture, file layout, workflow matrix, memory model, Claude Code setup |

## Verify your install

```bash
# Self-check the bundle (no global state needed)
pwsh ./scripts/validate-bundle.ps1
# Expects: 0 errors, 0 warnings

# Run the smoke tests (requires Pester 5+)
Install-Module Pester -MinimumVersion 5.0.0 -Scope CurrentUser -Force
pwsh -NoProfile -Command "Invoke-Pester ./tests/Pester/"
```

## Lifecycle reference (typical session)

```
$ pwsh ~/.agents/tools/pre-session.ps1 -Mode build -Task "add JWT auth"
  Scope:  SHARED -- packages/auth + middleware/ + 3 files
  Tier rec: TARGETED
  Swarm: parallel-reviewers (sequential implementer + N concurrent reviewers)
  Reflections: 2 unaddressed (repo=1, global=1)
  [emits BRIEF block to paste]

# Before spawning subagents, select the right model per role:
$ pwsh ~/.agents/tools/model-selector.ps1 -Scope SHARED -Role code-quality-reviewer
  {"model":"claude-sonnet-4-6","tier":"balanced","provider":"anthropic","trust_adjusted":false}

# ... agent does the work, marks gates as it goes:
$ pwsh ~/.agents/tools/state-gate.ps1 -SessionId <id> -Mark "context_loaded"
$ pwsh ~/.agents/tools/state-gate.ps1 -SessionId <id> -Mark "implementation_done"
$ pwsh ~/.agents/tools/state-gate.ps1 -SessionId <id> -Mark "verification_evidence"

$ pwsh ~/.agents/tools/post-session.ps1 -SessionId <id>
  Gate Status (scope: SHARED): all required gates passed
  Auto-consolidating reflections...
  auto-consolidated: 7 -> 2 (deduped=3 archived=1 stale=1 promoted=0)
  Session registered. Handoff: .kit/session-state/<id>/handoffs.md
```

Under Claude Code or OpenCode, `pre-session` and `post-session` fire automatically via hooks/plugin. Under Copilot CLI, the agent calls them itself per the baked instructions. Under Codex CLI / Kilo Code / generic, run them manually.

### How hook scripts resolve session metadata

The four lifecycle hook scripts (`session-start-hook.ps1`, `session-end-hook.ps1`, `subagent-stop-hook.ps1`, `precompact-hook.ps1`) accept session metadata from any of three transports, in priority order:

1. **CLI args** — `-SessionId`, `-Mode`, `-RepoRoot` etc. passed by the host (e.g. via `${CLAUDE_SESSION_ID}` substitution in `~/.claude/settings.json`).
2. **Env var** — `$env:CLAUDE_SESSION_ID` if set in the hook's environment.
3. **Stdin JSON** — Claude Code (and some other hosts) pipe `{"session_id": "...", "cwd": "...", "agent_name": "..."}` to hook commands. The kit reads stdin once via `Resolve-HookSessionId` in `_paths.ps1`, parses JSON, and resolves missing fields.

If all three transports are empty, the hook falls back to `unknown-{timestamp}` so the session still gets recorded — never crashes. Malformed JSON on stdin is swallowed gracefully.

This means the kit's hooks work out-of-the-box across Claude Code versions whether the host populates env vars, passes args, or pipes JSON — without manual settings tuning. End-to-end verified across all four hooks and four transport-failure modes.

## Frontend aesthetic direction (DESIGN.md)

The default LLM frontend output is recognizable: Inter, purple gradient, rounded cards, generic spacing. The kit's design critics (`ux-driver`, `ui-driver`, `design-driver`, `redesign`) all *judge* output against `DESIGN.md` — but nothing creates one. Result: parallel redesign agents each default to the same boring AI aesthetic and produce variations of one look instead of real exploration.

The `aesthetic-director` skill closes this gap. Pattern lifted from Anthropic's [Frontend Aesthetics Cookbook](https://platform.claude.com/cookbook/coding-prompting-for-frontend-aesthetics):

1. Pick the aesthetic *before* generating code
2. Encode it as a locked `DESIGN.md` (typography pairing, OKLCH palette, density, motion, banned-defaults list)
3. Optionally append a 5-10 line `CLAUDE.md` theme block so every future prompt in the repo holds to it

Invoked automatically by `/redesign` Phase 0 when no `DESIGN.md` exists. Standalone for "theme this project" tasks. Proposes 2-3 named directions from the vocabulary (Swiss Minimalism, Editorial, Brutalism, Glassmorphism, Dark OLED Luxury, Aurora Mesh, Solarpunk, Cyberpunk, etc.) — never one — and the user picks. Banned-defaults list is mandatory in every DESIGN.md to keep downstream agents from drifting back to LLM defaults.

The lightweight version: skip the skill, paste a `CLAUDE.md` theme block by hand:

```markdown
## Frontend Theme
<always_use_editorial_theme>
Always design with Editorial aesthetic:
- Serif headlines (e.g. Fraunces), sans body (e.g. Inter)
- Magazine grid, generous margins, pull quotes
- Muted palette: warm cream bg, near-black ink, single accent
- Banned: Inter for headlines, purple gradients, rounded-2xl cards
</always_use_editorial_theme>
```

Five lines, no install, locks the project's whole aesthetic.

## Important honesty

This kit is **pre-v1**. What that means in practice:

- **End-to-end runs are mostly unverified at scale.** The pieces work in isolation (validator + Pester + smoke tests all pass). Full multi-session usage across many repos hasn't been recorded. Test on a throwaway repo first.
- **Hook event names are best-effort verified against current docs.** Claude Code passes session metadata via stdin JSON, args (`${CLAUDE_SESSION_ID}` substitution), or env vars depending on version — kit hooks accept all three (see "How hook scripts resolve session metadata" above). OpenCode uses `session.created` / `session.deleted` event-handler keys (re-verified against opencode.ai/docs/plugins). If hooks don't fire, that's where to look.
- **Upgrade safety is via backup-and-replace.** `install.ps1 -Upgrade` moves `~/.agents/` to a timestamped backup before installing. Hand-merge customizations afterward. A proper override pattern (`~/.agents/overrides/{skill}.md`) isn't implemented yet.
- **CI is included but not yet exercised by external contributions.** `.github/workflows/validate.yml` runs validate-bundle + Pester on push and PR.

The kit is **opinionated by design**: hardcoded layout, explicit session artifacts, explicit write-routing, explicit review/build/plan lanes. It is not a zero-assumption framework. It is a disciplined operating system for serious coding work, and it asks you to follow its conventions in exchange for the loop closing automatically.

## Roadmap — future agents + tools

Concrete additions that fit the kit's leaf-agent + slash-command + shell-script architecture. Pick what you need; PRs welcome.

### High-value agents

| Agent | What it would do | Why |
|---|---|---|
| `release-manager` | Bumps `VERSION`, updates `CHANGELOG.md`, generates release notes from commits since last tag, opens release PR. | Every shipping team needs this; 30-min task humans repeat every release. |
| `migration-writer` | Writes DB schema migrations + rollback scripts. Reads `.kit/context/conventions.md` to use the right tool (Alembic / Prisma / Drizzle / Knex / etc.). | Migrations are the highest-risk part of any deploy; SOTA agents currently skip rollback scripts. |
| `pr-description-writer` | Pairs with `pr-reviewer`. Given a diff, writes a clear PR description (what + why + how-to-test). | Closes the loop: writer composes, reviewer approves. |
| `dependency-updater` | Surgical npm/pip/cargo lockfile updates with breaking-change scan. Reads CHANGELOG of each upgraded dep. | More careful than Dependabot, less noisy. |
| `incident-responder` | Production-incident analog of `/investigate`. Given a stack trace + recent deploy diff, hypothesis-driven debugging with on-call recommendations. | The Ops side of the kit. |
| `dead-code-finder` | Scans for unused exports, unreachable branches, redundant imports. Conservative — surfaces, doesn't auto-delete. | Quarterly cleanup; AI assistants are great at this. |
| `i18n-extractor` | Finds hardcoded user-visible strings, extracts to translation files. Conventions-aware (next-intl / react-intl / fluent / formatjs). | Common refactor, repeated everywhere. |
| `a11y-auditor` | Dedicated accessibility pass — keyboard nav, ARIA, screen-reader, contrast. Distinct from `ux-driver` (structural) and `ui-driver` (visual). | Accessibility is its own discipline; one focused agent beats generalist coverage. |
| `observability-auditor` | Finds missing logs, missing trace propagation, swallowed errors, key user-action paths without instrumentation. | Production-readiness gap that bites later. |
| `cost-tracker` | For AI/cloud apps: identifies expensive token / API calls, suggests caching, surfaces likely cost regressions in a diff. | LLM apps in particular need this. |

### High-value PowerShell tools

| Tool | What it would do |
|---|---|
| `pr-stats.ps1` | Extract PR metrics from local git history (avg size, time to merge, reviewer load). Feeds the conventions detector. |
| ~~`model-router.ps1`~~ `model-selector.ps1` **SHIPPED** | Picks the right model (haiku/sonnet/opus or GPT equivalents) per agent based on scope + role. Scope-aware + trust-aware; downgrades noisy agents via `agent-trust-scorer.ps1`; cross-provider ensemble routing on Copilot CLI; configurable via `MODEL_FAST` / `MODEL_BALANCED` / `MODEL_PREMIUM` env vars or `MODEL_MAP_FILE`. |
| `cost-estimator.ps1` | Pre-flight estimate of token cost for a planned task. Used in `goal-orchestrator`'s circuit breaker. |
| `lint-aggregator.ps1` | Run ALL configured linters (ts/eslint/ruff/clippy/etc.) and combine output into one greppable format. |
| `dep-graph.ps1` | Generate a dependency graph for the repo (used by `consequence` agent to trace blast radius mechanically). |
| `secret-scanner.ps1` | Scan for hardcoded secrets / keys / tokens. Faster than spawning the full security-reviewer agent. |
| `changelog-extract.ps1` | Given commits since last tag, generate a user-visible CHANGELOG entry. Pairs with `release-manager`. |

### Architectural improvements (kit-internal)

- **Goal-conditioned `/build` and `/review`** — extend the convergence-loop pattern beyond `goal-orchestrator` to other workflows so they self-iterate when verification fails.
- **Shared specialist-agent source** — currently 10 specialist agents are duplicated across `claude-code/.claude/agents/` and `opencode/.opencode/agents/`. Move to `_shared/specialist-agents/` with per-host frontmatter sanitization at install time. Same pattern as `_shared/workflow-agents/` already does.
- **OpenCode plugin: native subagent spawn instrumentation** — currently the plugin records lifecycle events but doesn't capture the tree of subagent spawns the way Claude Code's settings.json hooks do.
- **Copilot CLI workflow scripts: native version of writeback gate** — shell scripts at `~/.agents/bin/copilot/` should run `verify-writeback.ps1` at the end automatically (currently the workflow body's mechanical gate is Claude/OpenCode only).
- **MCP-server orchestration** (ruflo / claude-flow style) — the kit currently relies on description-matching auto-routing + slash commands. An MCP server providing `kit_build`, `kit_review` tools would give deterministic invocation across hosts that support MCP — at the cost of a server to maintain.

### Things explicitly NOT in the roadmap

- A "code generator agent" that writes whole modules from scratch. The kit's bet is on careful incremental change with verification gates. Greenfield generation belongs to `/redesign` (UI) and `workflow-implementer` invoked by `/build` (logic). One-shot module generation is shipped by other tools (Cursor's whole-file edits, GitHub Copilot Workspace).
- A "model router" subagent. Model selection is a tool concern, not an agent concern — confirmed by the implementation of `model-selector.ps1`, which ships as a standalone PS script called inline, not an agent.
- Replacing GitHub Copilot's built-in slash commands. Per the [Tier-E research](https://github.com/CBannink/agentic-coding-kit/pull/3), Copilot CLI's `/build`, `/review`, `/research`, `/fleet`, `/delegate` are owned by Copilot; user-defined slash commands aren't supported (issue #1113). The kit composes via shell scripts at `~/.agents/bin/copilot/` instead.

## License

MIT — see [LICENSE](./LICENSE). The kit packages or references patterns from
upstream projects (GStack, Superpowers, Autoresearch); see [NOTICE.md](./NOTICE.md)
for third-party attribution.

## Contributing

Contributions welcome. Before opening a PR:

```powershell
pwsh ./scripts/validate-bundle.ps1   # 0 errors, 0 warnings expected
pwsh ./scripts/doctor.ps1            # 0 fail, warnings allowed for optional features
Invoke-Pester ./tests/Pester/        # all tests should pass
```

The CI workflow at `.github/workflows/validate.yml` runs the same on every push.

## About / Author

Built by **Caspar Bannink** in Dublin.

- Founder of [HomeScout.io](https://homescout.io) — AI-powered home search.
- Previously Senior Full-Stack & AI Engineer at Incogniton, where I built **CAS**
  — their in-app AI assistant — solo, end-to-end. CAS shipped with RAG over the
  product knowledge base, prompt caching, MCP integration, in-chat NLP that
  drives the UI directly (account management, navigation, settings) by calling
  tools that operate the interface, multi-tool agent flows, and the rest of the
  fun stuff modern agentic apps need.
- Personal LinkedIn: [linkedin.com/in/caspar-bannink-719440217](https://www.linkedin.com/in/caspar-bannink-719440217/)
- Company LinkedIn (HomeScout.io): [linkedin.com/company/homescout-io](https://www.linkedin.com/company/homescout-io)
- Medium: [@CasparAI](https://medium.com/@CasparAI) — writing on AI / agentic coding / what works

This kit is the harness I use across my own projects. It's opinionated because
it reflects what I've found works in production agentic-coding workflows.
Open-sourced in the hope it's useful to others running similar setups. Issues
and PRs welcome.
