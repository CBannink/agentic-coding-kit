# Caspar Bannink Agentic Coding Kit

A cross-harness agentic workflow kit for serious coding, review, product, and
marketing work. It installs one shared operating layer under `~/.agents/`, then
renders the right skills, agents, instructions, and wrappers for each host.

Primary mature harnesses:

- Claude Code
- Codex
- OpenCode
- GitHub Copilot CLI

Additional lightweight adapters exist for generic `AGENTS.md` and
Gemini-style layouts, but the strongest subagent workflow is on the four
primary harnesses above. Kilo Code support has been removed from the supported
installer surface.

## What It Does

The kit makes the main session an orchestrator first. The main agent classifies
the request, loads the smallest relevant indexed context, defines the expected
test set, then delegates concrete work to specialized workflow or specialist
agents. It avoids the common failure mode
where the main chat keeps every file, every diff, every reviewer thought, and
every implementation detail in one bloated context.

The root prompts bias toward cost-aware delegation: the orchestrator may read
the directly relevant files needed to route well, but real exploration goes to
`workflow-explorer`; obvious mechanical edits across at most 3 files may stay
inline; coding likely to touch more than 3 files, add files, cross modules, or
need unfamiliar conventions goes to `workflow-implementer` or the hard
implementer variant.

Core behavior:

- Plan/build/review/investigate/refactor/security/redesign workflows.
- Lean default agents for exploration, implementation, UI QA, code quality,
  conditional security review, and UI route/UX/visual checks.
- Additional specialist, product, marketing, prompt-synthesis, and learning
  agents remain in source for explicit manual use, not default install/routing.
- Minimal repo context: current code first, `.wiki/index.md` only as an
  on-demand index, `.kit/context/patterns.md` only when focused guidance helps.
- Test-set-first build loop: define expected unit/integration/E2E coverage
  before implementation, using mock data or fixtures where possible.
- Verification gates: no completion claim without fresh build/test/lint
  evidence.
- Lazy global loop skills for `test-strategy`, `silent-failure-hunter`,
  `verification-before-completion`, and `skill-import`; these are available
  across hosts but are not default agents or startup context.
- Self-improvement tools remain installed for explicit manual maintenance, but
  they are not normal workflow gates.
- Cross-harness install: the same canonical agent sources are rendered into
  Claude/OpenCode markdown, Codex TOML, and Copilot `.agent.md`.

## Quick Install

Run from the kit checkout:

```powershell
# Recommended: install one harness with its dedicated script
pwsh .\scripts\install-codex.ps1
pwsh .\scripts\install-copilot.ps1
pwsh .\scripts\install-claude.ps1
pwsh .\scripts\install-opencode.ps1

# Advanced shared backend: install for multiple harnesses
pwsh .\scripts\install.ps1 -For "codex,copilot"

# Install for all supported device-wide targets
pwsh .\scripts\install.ps1 -For all

# Auto-detect installed CLIs on PATH
pwsh .\scripts\install.ps1 -Auto
```

Which command to use:

| Situation | Command |
|---|---|
| Fresh machine, one host | `pwsh .\scripts\install-<codex|copilot|claude|opencode>.ps1` |
| Fresh machine, several hosts | Run the dedicated scripts you want, or use `pwsh .\scripts\install.ps1 -For "codex,copilot"` |
| Fresh machine, install every mature target | `pwsh .\scripts\install.ps1 -For all` |
| Existing repo that needs `.kit` and `.wiki` | `pwsh .\scripts\install-<host>.ps1 -BootstrapHarness -TargetRepo C:\path\to\repo` |
| Existing Codex setup with hand-tuned `~/.codex/agents/*.toml` models | Do a manual Codex port and preserve `model = ...` lines |

Verify:

```powershell
pwsh .\scripts\validate-bundle.ps1
pwsh .\scripts\doctor.ps1
```

Expected current baseline: `validate-bundle.ps1` has `0` errors. Existing
warnings are non-blocking unless you are specifically working on those areas.

## Per-Harness Install Details

### Codex

```powershell
pwsh .\scripts\install-codex.ps1
```

Installs:

- `~/.codex/AGENTS.md` with the orchestrator rules block.
- `~/.codex/agentic-kit.md` long-form reference.
- `~/.codex/skills/*/SKILL.md`.
- `~/.codex/agents/*.toml`.
- `~/.codex/agents/orchestrator.toml` from the single shared primary
  orchestrator template.
- `~/.codex/config.toml` runtime posture:
  - `approval_policy = "never"`
  - `sandbox_mode = "danger-full-access"`
  - `multi_agent = true`
  - `hooks = false`

Codex receives the lean default agent set only:

- `workflow-explorer`, `workflow-implementer`, `workflow-ui-qa`
- `code-quality-reviewer`, `security-reviewer`
- `playwright-navigator`, `ux-driver`, `ui-driver`

The portable kit source contains no model references. Local model routing, if
used, belongs only in `~/.codex/config.toml` and `~/.codex/agents/*.toml`.

Important: if your Codex install already has hand-tuned submodel routing in
`~/.codex/agents/*.toml`, do not refresh it with the installer unless you have
backed up those files or intentionally want the generated model-neutral TOML.
Manually merge the new agent bodies and preserve each `model = ...` line.

### GitHub Copilot CLI

```powershell
pwsh .\scripts\install-copilot.ps1
```

Installs:

- `~/.copilot/copilot-instructions.md`.
- `~/.copilot/agentic-kit.md`.
- `~/.copilot/agents/*.agent.md`.
- `~/.copilot/agents/orchestrator.agent.md` from the single shared primary
  orchestrator template.
- `~/.copilot/settings.json` display-noise settings:
  - `streamerMode = true`
  - `terminalProgress = false`
  - no `effortLevel` override.
- `~/.agents/bin/copilot/kit-*.ps1` and `kit-*.sh` wrapper scripts.

Copilot receives the same lean default agent set as `.agent.md` files.

Copilot CLI has no documented user slash-command surface, so this kit uses
global instructions, custom agents, and wrapper scripts instead. Repo-scoped
Copilot install also writes `.github/agents`, `.github/copilot-bin`, and
`.github/hooks` when you install the repo adapter.

### Claude Code

```powershell
pwsh .\scripts\install-claude.ps1
```

Installs:

- `~/.claude/CLAUDE.md` orchestrator instructions.
- `~/.claude/agentic-kit.md`.
- `~/.claude/skills/*/SKILL.md`.
- `~/.claude/commands/*.md`.
- `~/.claude/agents/*.md`.
- `~/.claude/agents/orchestrator.md` from the single shared primary
  orchestrator template.
- Claude settings hook wiring via the merger.

Claude receives the same shared workflow and specialist agent set, rendered as
Claude-compatible markdown.

### OpenCode

```powershell
pwsh .\scripts\install-opencode.ps1
```

Installs:

- `~/.config/opencode/AGENTS.md`.
- `~/.config/opencode/agentic-kit.md`.
- `~/.config/opencode/skills/*/SKILL.md`.
- `~/.config/opencode/commands/*.md`.
- `~/.config/opencode/agents/*.md`.
- `~/.config/opencode/agents/orchestrator.md` from the single shared primary
  orchestrator template.
- `~/.config/opencode/opencode.jsonc` with `default_agent` set to
  `orchestrator`.
- `~/.config/opencode/plugins/agentic-kit.ts`.

OpenCode receives the lean default agent set as sanitized markdown agents.

## Bootstrap A New Repo

In a new repo, run bootstrap before expecting high-quality repo-aware coding.
The installer command plants the scaffold and repo adapters:

```powershell
pwsh .\scripts\install-copilot.ps1 -BootstrapHarness -TargetRepo C:\path\to\repo
```

Use the dedicated script for the harness you want in that repo. Then complete
the AI bootstrap phases. In an agent session, ask:

```text
bootstrap this repo
```

or invoke the bootstrap skill/command if your host exposes it:

```text
/bootstrap-harness
```

For Copilot CLI, the repo-local wrapper is the self-driving path:

```powershell
pwsh .\.github\copilot-bin\kit-bootstrap.ps1 C:\path\to\repo
```

Scaffold alone may contain placeholders. A completed bootstrap creates and
populates:

- `.kit/context/patterns.md`
- `.kit/context/conventions.md`
- `.kit/context/workflow-briefs/<workflow-agent>.md`
- `.kit/workflows/`
- `.wiki/index.md`
- `.wiki/architecture.md`
- `.wiki/codebase.md`
- `.wiki/features.md`
- `.wiki/.features`
- host repo adapters such as `AGENTS.md`, `CLAUDE.md`, and
  `.github/copilot-instructions.md`

The bootstrap flow must replace placeholders with real repo facts. The gate
fails if files still contain `PLACEHOLDER`, `_not yet detected_`, or
`Generated by: _not yet run_`.

The completed gate must include the core workflow briefs:

- `workflow-explorer.md`
- `workflow-implementer.md`
- `workflow-ui-qa.md`

After bootstrap, the most important quality signal is not that the files exist;
it is that workflow agents can find compact, repo-specific guidance before they
touch code. In practice, check that `.kit/context/workflow-briefs/` contains
real notes for explorer, implementer, and UI QA, and that `.wiki/index.md`
points to useful architecture/codebase pages.

## Existing Repo With Its Own Rules

If a repo already has `AGENTS.md`, `CLAUDE.md`, memory files, or another
agentic workflow, do not blindly replace it. Use:

```powershell
pwsh .\scripts\install.ps1 -For all
```

Then in that repo:

```text
/kit-migrate
```

`kit-migrate` preserves domain preferences while converging structural state:

- where session state goes
- where handoffs go
- where repo memory goes
- how repo context patterns and legacy role memory are routed
- how workflow state is recorded

Repo-specific build commands, deploy rules, coding style, and product context
remain repo-owned.

## Orchestrator-First Philosophy

The main agent is the coordinator, not the default implementer.

Routing model:

- trivial single-file mechanical work can stay inline
- unfamiliar work uses `workflow-explorer`
- multi-file coding uses `workflow-implementer`
- review uses one `code-quality-reviewer`
- security review is added only for real trust-boundary risk
- UI behavior uses `workflow-ui-qa`, `ux-driver`, and `ui-driver`
- autonomous multi-step work uses the active `/goal` loop
- heavy-loop learning tools are manual maintenance

The main agent should keep its own context small, pass precise briefs to leaf
agents, read their summaries, and verify the result. For code changes, it also
owns the test strategy: add or update the relevant unit, integration, contract,
or E2E tests, use mock data/fixtures for external surfaces, and record why if
E2E is infeasible.

## Workflows

The kit ships 13 shared workflow command templates:

- `analyze`
- `bootstrap-harness`
- `build`
- `goal`
- `investigate`
- `kit-init`
- `kit-migrate`
- `plan`
- `redesign`
- `refactor`
- `review`
- `security-review`
- `wiki-init`

Main workflows:

- `/plan`: scope and design before implementation.
- `/build`: minimal context, expected test set, implement with tests, verify,
  unified review, repair loop.
- `/test-gen`: focused test-writing loop for large missing coverage; useful
  inside `/build` after the expected test set is known.
- `/review`: unified diff review with false-positive checking.
- `/investigate`: hypothesis-driven root cause analysis.
- `/refactor`: behavior-preserving restructuring.
- `/redesign`: aesthetic lock, browser capture, UX/UI critique, visual verify.
- `/security-review`: attack-class review for auth/input/secrets/IO surfaces.
- `/goal`: autonomous convergence loop for mixed or ambiguous work.
- `/bootstrap-harness`: initialize `.kit` and `.wiki`.

Hosts without native slash commands still use the same skill bodies through
instructions, description matching, or wrapper scripts.

## Agents

### Workflow Agents

- `workflow-explorer`: bounded file discovery and pattern mapping.
- `workflow-implementer`: multi-file implementation.
- `workflow-ui-qa`: user-flow/defaults/artifact-safety QA.

### Engineering Specialists

- `code-quality-reviewer`
- `security-reviewer`
- `playwright-navigator`
- `ux-driver`
- `ui-driver`

`code-quality-reviewer` is the single default post-verification reviewer for
normal build/review/refactor/redesign flows. `security-reviewer` is the only
optional default specialist and is used only for trust-boundary risk. UI agents
run only when route discovery, UX, or visual review is relevant.

### Lazy Loop Skills

- `test-strategy`: define the expected test set before implementation.
- `silent-failure-hunter`: focused review for swallowed errors and false success.
- `verification-before-completion`: check that verification evidence is fresh.
- `skill-import`: normalize external skill ideas without importing runtime bloat.

These are global skills installed with the kit. They stay on demand and do not
add reviewers, startup context, lifecycle hooks, or memory gates.

### Manual Compatibility Agents

Product, marketing, business, prompt-synthesis, legacy reviewer/verifier, and
learning agents remain in `bundle/adapters/_shared/specialist-agents/` for
explicit manual installs or experiments. They are not part of the default
Codex/Copilot/OpenCode install surface.

## Context Model

Default coding context is current request plus current code. The kit keeps a
small optional knowledge base, but it is not startup context:

- `.wiki/index.md`: on-demand index into architecture, codebase, features, and
  principles.
- `.kit/context/patterns.md`: optional focused repo guidance.
- `.kit/session-state/`: run evidence and private session artifacts.

Memory files, handoffs, reflections, and legacy role-specific guidance are
manual maintenance or compatibility surfaces. They are not completion gates and
should not be bulk-read in normal coding loops.

## `.wiki` Retrieval

`.wiki` is the human/codebase knowledge layer:

- `.wiki/index.md`: table of contents.
- `.wiki/architecture.md`: boundaries, layers, ownership.
- `.wiki/codebase.md`: where important code lives.
- `.wiki/features.md`: user-visible behavior.
- `.wiki/.features`: machine-readable feature index.

Agents use `.wiki` to avoid rediscovering the repo from scratch and to detect
documentation drift when user-visible behavior changes.

## Manual Self-Improvement

The kit has a controlled learning surface:

1. Reflections and memory inbox entries are stored for explicit review.
2. `auto-consolidate.ps1`, `compress-memory.ps1`, `harness-propose.ps1`,
   `auto-apply-reflect.ps1`, `prompt-improver.ps1`, and `memory-inbox.ps1`
   remain available as manual maintenance tools.
3. Normal completion is not blocked by reflection backlog, writeback warnings,
   wiki updates, memory updates, or handoff writes.
4. Completion means requested behavior is done, fresh checks are green, and no
   unhandled BLOCKING finding remains from the unified reviewer.

This is deliberately conservative. The kit should learn, but normal coding
loops should stay focused on implementation, verification, and one useful
review.

## Safety and Validation

Installer safety:

- `validate-bundle.ps1` runs before install.
- Repo-template install only fills missing files; it does not overwrite
  generated `.kit/context` memory on rerun.
- Workflow brief templates are explicit placeholders and bootstrap rejects
  placeholder content.
- Portable kit source is model-neutral.
- Codex hooks are disabled by default because they caused terminal-spawn noise.

Run:

```powershell
pwsh .\scripts\validate-bundle.ps1
pwsh .\scripts\doctor.ps1
```

Useful checks:

- `validate-bundle.ps1`: bundle source health.
- `doctor.ps1`: installed host health.
- `scripts/install.ps1 -CleanReinstall -For <host>`: refresh stale managed
  host dirs while preserving runtime state.

## Repository Layout

| Path | Purpose |
|---|---|
| `bundle/global/.agents/skills/` | global skills installed into host skill dirs |
| `bundle/global/.agents/tools/` | classifiers, gates, resolvers, hooks, validators |
| `bundle/global/.agents/context/` | protocols and global specialist memory |
| `bundle/adapters/_shared/workflow-agents/` | canonical workflow agents |
| `bundle/adapters/_shared/specialist-agents/` | canonical specialist agents |
| `bundle/adapters/_shared/workflow-commands/` | canonical workflow command bodies |
| `bundle/adapters/{claude-code,codex-cli,copilot-cli,opencode,...}/` | host adapters |
| `bundle/repo-template/` | files planted into repos during bootstrap |
| `scripts/install.ps1` | main installer |
| `scripts/doctor.ps1` | installed-system diagnostic |
| `scripts/validate-bundle.ps1` | source bundle diagnostic |
| `docs/` | deeper architecture/setup docs |

## Current Production Notes

- The mature target set is Claude Code, Codex, OpenCode, and GitHub Copilot CLI.
- Copilot has the weakest command surface, so it relies on global instructions,
  `.agent.md` agents, and wrapper scripts.
- Codex local model routing is intentionally local-only and not part of the
  portable kit.
- Hooks are useful but not required for the kit to function. Codex hooks are
  installed disabled by default.
- New repos should run `bootstrap-harness`; otherwise agents fall back to
  generic best practices.

## License

MIT. See [LICENSE](./LICENSE).
