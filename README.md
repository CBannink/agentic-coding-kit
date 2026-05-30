# Caspar Bannink Agentic Coding Kit

A cross-harness agentic workflow kit for serious coding, review, product, and
marketing work. It installs one shared operating layer under `~/.agents/`, then
renders the right skills, agents, instructions, and wrappers for each host.

Primary mature harnesses:

- Claude Code
- Codex
- OpenCode
- GitHub Copilot CLI

Additional lightweight adapters exist for generic `AGENTS.md`, Kilo Code, and
Gemini-style layouts, but the strongest subagent workflow is on the four
primary harnesses above.

## What It Does

The kit makes the main session an orchestrator first. The main agent classifies
the request, loads the relevant repo memory, then delegates concrete work to
specialized workflow or specialist agents. It avoids the common failure mode
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
- Shared workflow agents for exploration, implementation, review, skepticism,
  UI QA, and prompt compression.
- Shared specialist agents for code quality, security, modularity, PR review,
  UX/UI, QA, product, marketing, cold email, offers, content, support, and
  self-improvement.
- Repo-local `.kit/` memory for architecture, conventions, workflow briefs, and
  role-specific guidance.
- Repo-local `.wiki/` for codebase maps, architecture, user-visible features,
  and retrieval during coding.
- Verification gates: no completion claim without fresh build/test/lint
  evidence.
- Self-improvement loop: session reflections, auto-consolidation, bounded
  specialist memory, memory inbox/review, and proposal generation for kit-level
  changes.
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

Codex receives:

- 6 shared workflow agents.
- 28 shared specialist agents.
- Codex adapter agents.

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

Copilot receives:

- 6 shared workflow agents.
- 28 shared specialist agents.

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

OpenCode receives the same shared workflow and specialist agent set, sanitized
for OpenCode frontmatter.

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

- `.kit/context/memory.md`
- `.kit/context/conventions.md`
- `.kit/context/reusables.md`
- `.kit/context/agent-memory/shared.md`
- `.kit/context/workflow-briefs/<workflow-agent>.md`
- `.kit/context/handoffs.md`
- `.kit/context/history.md`
- `.kit/context/reflections.md`
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

The completed gate must include `.kit/context/reusables.md` and all six core
workflow briefs:

- `workflow-explorer.md`
- `workflow-implementer.md`
- `workflow-reviewer.md`
- `workflow-skeptic.md`
- `workflow-ui-qa.md`
- `prompt-synthesizer.md`

After bootstrap, the most important quality signal is not that the files exist;
it is that workflow agents can find compact, repo-specific guidance before they
touch code. In practice, check that `.kit/context/workflow-briefs/` contains
real notes for explorer, implementer, reviewer, skeptic, UI QA, and prompt
synthesis, and that `.wiki/index.md` points to useful architecture/codebase
pages.

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
- how specialist memory is routed
- how workflow state is recorded

Repo-specific build commands, deploy rules, coding style, and product context
remain repo-owned.

## Orchestrator-First Philosophy

The main agent is the coordinator, not the default implementer.

Routing model:

- trivial single-file mechanical work can stay inline
- unfamiliar work uses `workflow-explorer`
- multi-file coding uses `workflow-implementer`
- review uses `workflow-reviewer` or specialist reviewers
- risky plans/diffs use `workflow-skeptic`
- UI behavior uses `workflow-ui-qa`, `ux-driver`, and `ui-driver`
- autonomous multi-step work uses `goal-orchestrator`
- heavy loops can use `learning-curator`

The main agent should keep its own context small, pass precise briefs to leaf
agents, read their summaries, and verify the result.

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
- `/build`: explore, synthesize prompt, implement, review, verify, handoff.
- `/review`: diff review with false-positive checking.
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
- `workflow-reviewer`: scoped diff review.
- `workflow-skeptic`: assumption ledger and hidden failure modes.
- `workflow-ui-qa`: user-flow/defaults/artifact-safety QA.
- `prompt-synthesizer`: compresses noisy handoffs without losing constraints.

### Engineering Specialists

- `code-quality-reviewer`
- `security-reviewer`
- `modularity-expert`
- `adversarial-reviewer`
- `qa-reviewer`
- `spec-reviewer`
- `final-verifier`
- `goal-reviewer`
- `slop-refactorer`
- `playwright-navigator`
- `ux-driver`
- `ui-driver`
- `pr-reviewer`

### Product, Marketing, and Business Specialists

- `product-strategist`
- `marketing-strategist`
- `positioning-messaging-expert`
- `growth-experimenter`
- `customer-researcher`
- `copywriter`
- `sales-enablement-expert`
- `business-model-analyst`
- `cold-email-strategist`
- `content-strategist`
- `offer-architect`
- `landing-page-critic`
- `customer-support-analyst`

### Orchestration and Learning

- `goal-orchestrator`
- `learning-curator`

`learning-curator` runs only after heavy build/review loops. It can append up
to 5 high-confidence cross-repo lessons to bounded global specialist memory via
`specialist-memory-append.ps1`; uncertain lessons go to reflections.

## Memory Model

The kit separates memory by durability and scope.

| Memory | Path | Purpose |
|---|---|---|
| Repo facts | `.kit/context/memory.md` | durable architecture, commands, constraints |
| Repo conventions | `.kit/context/conventions.md` | detected git, PR, testing, architecture style |
| Reusables | `.kit/context/reusables.md` | compact index of reusable APIs/components/utilities |
| Workflow briefs | `.kit/context/workflow-briefs/<agent>.md` | per-workflow-agent preload, under 5000 tokens |
| Repo specialist memory | `.kit/context/agent-memory/<role>.md` | role-specific repo guidance |
| Global specialist memory | `~/.agents/context/specialist-memory/<role>.md` | cross-repo specialist lessons |
| Session state | `.kit/session-state/<id>/` or `~/.agents/session-state/<id>/` | run packets, evidence, handoffs |
| Reflections | `.kit/context/reflections.md`, `~/.agents/context/reflections.md` | self-improvement candidates |

During coding:

1. The workflow agent reads its own workflow brief first.
2. It falls back to `memory.md`, `conventions.md`, `reusables.md`, and relevant
   `.wiki` pages only when needed.
3. Specialist agents receive global specialist memory, then repo-local
   specialist memory, through `specialist-memory-resolver.ps1`.
4. The orchestrator should not bulk-read the entire wiki unless the task truly
   needs it.

## `.wiki` Retrieval

`.wiki` is the human/codebase knowledge layer:

- `.wiki/index.md`: table of contents.
- `.wiki/architecture.md`: boundaries, layers, ownership.
- `.wiki/codebase.md`: where important code lives.
- `.wiki/features.md`: user-visible behavior.
- `.wiki/.features`: machine-readable feature index.

Agents use `.wiki` to avoid rediscovering the repo from scratch and to detect
documentation drift when user-visible behavior changes.

## Self-Improvement Loop

The kit has a controlled learning loop:

1. Workflows and hooks emit reflections when agents miss something, repeat a
   false positive, or discover a durable workflow issue.
2. `post-session.ps1` runs auto-consolidation and memory compression.
3. Safe repeated patterns can be promoted mechanically.
4. Risky routing/gating/verification changes remain in reflections until
   `/reflect` or human review.
5. `learning-curator` can write bounded global specialist memory after heavy
   loops.
6. `harness-propose.ps1` creates proposals for recurring kit-level changes.

This is deliberately conservative. The kit should learn, but it should not
silently rewrite core prompts or scripts from a single noisy session.

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
