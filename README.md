# Agentic Coding Kit v6.3

A native, development-focused workflow kit for long-horizon coding work in
Codex, Claude Code, OpenCode, and GitHub Copilot CLI. The active harness session
is the orchestrator. Skills define reusable loops; small, bounded agents keep
exploration, implementation, review, testing, and specialist judgment out of
the main context.

The kit is intentionally model-neutral. It does not force one provider's model
names into another harness.

## Current release highlights

- One host-native primary orchestrator owns the outcome; specialists never
  become nested orchestrators or dispatch successors.
- `INLINE` handles clear bounded work; `LOOP` keeps one strong primary in
  control of Anchor, Plan, Dispatch, Integrate, Verify, and bounded repair.
- Agent returns use only `Result`, `Evidence`, and optional `Next`, keeping
  handoffs compact and leaving validation with the active session.
- Tests, independent review, browser QA, UI critique, and security review are
  conditional evidence gates rather than ceremonial stages.
- Agents load only the exact repository wiki sections supplied to them, verify
  those claims against current source, report drift, and never edit `.wiki`.
- Managed installation preserves explicit configuration where supported,
  handles malformed or linked state safely, and keeps generated host adapters
  deterministic across Codex, Claude Code, OpenCode, and Copilot CLI.

## Start here

### Requirements

- Windows or macOS.
- Node.js 20 or newer. The current release is a bundled JavaScript CLI, not a
  standalone native executable.
- At least one supported harness installed separately: `codex`, `claude`,
  `opencode`, or `copilot`.
- Git for project-scope installation and wiki initialization.

Build the management CLI once from the repository root. Use these exact
commands; the repository root itself has no `package.json`:

```powershell
npm ci --prefix cli
npm run bundle --prefix cli
```

On macOS, use the same commands in Terminal.

`esbuild` is a required source-install dependency, so this also works on
machines configured with `NODE_ENV=production` or `npm config omit=dev`. If an
older checkout reports that `esbuild` is not recognized, run
`npm ci --prefix cli --include=dev`, then rebuild, or pull the latest `main`.

### Install

> **Warning: a user-scope install replaces the selected harness's complete
> global instructions, agents, skills, commands, and primary configuration
> file.** Back up or copy any custom agents, skills, model settings, MCP
> servers, hooks, permissions, or instructions you want to keep. The installer
> does not attempt to merge or classify the previous configuration.

The installer prints the warning and asks for `Y/N` confirmation before making
changes. Use `--yes` only for deliberate non-interactive installation.

Windows, install adapters for all four harnesses:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-all.ps1 `
  --scope user --profile core --security preserve --memory preserve
```

macOS:

```bash
bash scripts/install-all.sh \
  --scope user --profile core --security preserve --memory preserve
```

For one harness, use `install-codex`, `install-claude`, `install-opencode`, or
`install-copilot` with the platform's `.ps1` or `.sh` suffix.

`core` installs every coding loop and all eight core agents. Use `full` only
when browser execution and visual UI critique are useful.

For a non-interactive install with Codex explicitly configured for unrestricted
local execution:

```powershell
.\scripts\install-all.ps1 --scope user --profile full `
  --security permissive --memory preserve `
  --yes
```

On macOS:

```bash
bash scripts/install-all.sh --scope user --profile full \
  --security permissive --memory preserve \
  --yes
```

`permissive` emits Codex `approval_policy = "never"` and
`sandbox_mode = "danger-full-access"`, plus managed OpenCode global and
per-agent `allow` permissions. Other harnesses retain their native permission
semantics; the kit does not invent unsupported parity fields.

An all-host install performs a complete dry-run preflight before changing any
host. Files are then installed sequentially. Project-scope installation does
not clear user-global harness configuration.

## What gets installed

### Ten core skills

| Skill | Purpose |
|---|---|
| `build` | Implement features, fixes, refactors, migrations, UI, API, data, configuration, and code-linked documentation. |
| `design` | Produce a feature, product, prototype, or UI design before implementation. |
| `architecture` | Assess or design repository boundaries, ownership, dependencies, and maintainability. |
| `grill` | Run an explicitly requested one-question-at-a-time decision interview. |
| `analyze` | Read-only diagnosis, explanation, comparison, architecture, dependency, and performance analysis. |
| `review` | Independent review of a diff, branch, contract, design, subsystem, or test delta. |
| `pr-ready` | Repair and package a diff for efficient human PR review. |
| `threat-model` | Read-only trust-boundary, attack-path, control, and mitigation analysis. |
| `wiki` | Initialize, reinitialize, or audit curated repository engineering knowledge. |
| `experiment` | Compare prompts, agents, models, algorithms, benchmarks, or harness variants under a frozen evaluation. |

These are general development workflows. They are not ten mandatory stages.
The orchestrator chooses the smallest useful loop and may work inline for a
clear, low-risk change.

### Two execution modes

- `INLINE`: direct work only for a minimal task whose implementation context,
  behavioral contract, and proof are already present before routing.
- `LOOP`: used when discovery or implementation would consume substantial
  primary context, the change spans distinct responsibilities or contracts, or
  fresh judgment should improve correctness. The primary keeps the goal and
  plan, dispatches one coherent Coder by default or a few path-isolated Coders
  when safely partitioned, integrates and verifies the result, sends it to a
  fresh combined Reviewer, and bounds repair.

File count is only a hint. The model chooses the route; no agent is spawned for
ceremony. New tests and the Test Engineer remain conditional evidence rather
than mandatory stages.

The routes and retry policy are prompt policy, not a rigid TypeScript workflow
engine. Tested structural helpers validate selected packet, freshness, and
repair-budget shapes, but do not automatically route agents or enforce
handoffs/retries at model runtime. The main model decides which useful route
comes next and when the requested outcome is sufficiently proven.

Design uses `INLINE DESIGN`, `DESIGN LOOP`, or `UI STUDIO`; comparative
prototypes route through Experiment and production promotion returns through
Build. PR preparation uses `INLINE` or `LOOP`. Threat modeling keeps its
focused domain playbooks. Failed repair cycles stop after four unsuccessful
rounds and return evidence to the user.

### Eight core agents

| Agent | Responsibility | Writes |
|---|---|---|
| `architect` | Repository-grounded architecture and change-boundary decisions. | No |
| `repo-scout` | Bounded repository discovery and evidence mapping. | No |
| `coder` | Coherent production implementation and useful durable behavior evidence. | Production and tests |
| `reviewer` | Independent code, design, and test-delta judgment. | No |
| `test-engineer` | Independent high-value test hardening. | Tests and fixtures only |
| `diagnostician` | Discriminate repeated or ambiguous failures. | No |
| `sage` | Rare principal-engineering challenge for difficult decisions. | No |
| `security-reviewer` | Concrete review of material trust-boundary changes. | No |

The `full` profile additionally installs:

- `browser-qa`: browser execution and evidence capture.
- `ui-critic`: independent visual and UX critique.

All agent returns go to the main orchestrator. Assignments carry the goal and
acceptance criteria, plan decision, workspace baseline, starting paths, exact
wiki sections or `NONE`, boundaries, and stop condition. Writer returns include
status, summary, exact changed paths, evidence, and only a remaining blocker or
route. The orchestrator checks the live diff, scope, and freshness before
creating the next fresh assignment. Completed specialists are never
reactivated, and transcripts are never forwarded.

## Repository wiki

`wiki init` and `wiki reinit` build an architect-grade map of how the repository
actually works: entry points, vertical control/data flows, module boundaries,
APIs, integrations, branching and error conventions, code organization,
canonical examples, tests, CI, and workspace-specific differences.

The required pages are:

```text
.wiki/index.md
.wiki/repository-map.md
.wiki/architecture.md
.wiki/engineering.md
```

Initialization uses deterministic inventory, one Orientation Scout, one to
three targeted evidence scans, orchestrator synthesis, independent review, and
a parser-backed writer/audit. Schema-v2 synthesis gives every page a concise
summary and activation signals, and every section a stable anchor, claim type,
and exact source or symbol evidence. The index routes task signals directly to
those sections so agents can start from a narrow, verified context packet
instead of rediscovering the whole repository. Convention claims require an
authoritative repository source or two independent current-code examples.
Evidence hashes make later source drift visible to `wiki audit`. Normal build
sessions never update the wiki.

An existing unmarked or legacy wiki is never overwritten implicitly. Preview
and explicitly adopt it when replacement is intended:

```text
kit wiki reinit --adopt-existing --dry-run --synthesis <reviewed-json>
kit wiki reinit --adopt-existing --yes --synthesis <reviewed-json>
```

Adoption backs up the complete previous `.wiki` under
`.git/agentic-kit/wiki-backups/` before installing the reviewed map.

Optional PR-history learning is a two-pass operation available only during
wiki initialization or reinitialization:

```text
kit wiki collect-pr-history
bounded history Scout -> candidate lessons and PR/thread IDs
current-source validation and independent review
kit wiki reinit --synthesis <reviewed-json>
```

It supports authenticated GitHub/GitHub Enterprise and Azure DevOps tooling,
examines at most 120 days, 100 merged PRs, and 1,000 human threads, and stores
raw evidence only under `.git/agentic-kit/pr-history/`. Only repeated,
accepted, current-source-backed lessons may enter
`.wiki/review-practices.md`, which is capped at 20,000 characters.

## Native harness locations and invocation

| Harness | User agents | User skills | Typical invocation |
|---|---|---|---|
| Codex | `~/.codex/agents/*.toml` | `~/.agents/skills/<name>/SKILL.md` | `$build ...`, `$review ...` |
| Claude Code | `~/.claude/agents/*.md` | `~/.claude/skills/<name>/SKILL.md` | `/build ...`, `/review ...` |
| OpenCode | `~/.config/opencode/agents/*.md` | `~/.config/opencode/skills/<name>/SKILL.md` | `/build ...` thin command or native skill |
| Copilot CLI | `~/.copilot/agents/*.agent.md` | `~/.copilot/skills/<name>/SKILL.md` | Say "Use the build skill..."; inspect with `/skills`; select agents with `/agent` |

Project scope uses `.codex/agents` plus `.agents/skills`, `.claude/agents` plus
`.claude/skills`, `.opencode/agents` plus `.opencode/skills`, and
`.github/agents` plus `.github/skills` respectively. ACK does not write its
primary policy into `AGENTS.md` for Codex or OpenCode. Codex receives it through
the root `developer_instructions` setting in `config.toml`; OpenCode receives it
only in the managed `agentic-kit` primary. Existing repository instructions
remain host-native repository context, not ACK's orchestration channel. Claude
and Copilot use their managed native instruction files.

OpenCode additionally installs `agents/agentic-kit.md` as the managed
`mode: primary` engineering agent. The other named agents are bounded
`mode: subagent` specialists that return to that primary; they are not alternate
orchestrators. On a clean install, or when OpenCode config has no explicit
`default_agent`, the installer selects `agentic-kit`. An existing explicit
non-kit default is preserved. Pass `--set-default-agent` only to override that
existing choice. Updates keep the primary installed and retain kit-owned
default restoration metadata; uninstall removes the primary and restores the
previous custom default, or removes the kit-owned default when none existed.
JSONC comments and unrelated settings are preserved. At each scope the installer
uses the sole existing `opencode.json` or `opencode.jsonc`; if both exist at that
scope it fails safely before writing and asks you to remove one or set
`OPENCODE_CONFIG`. Project or managed OpenCode configuration with higher native
precedence may override user-scope settings; the installer does not control
every OpenCode configuration layer.

The managed primary contains the canonical ACK orchestrator plus a very small
OpenCode runtime note. OpenCode specialists deny skill loading and successor
dispatch, so they receive only their role prompt and the primary's bounded
assignment. The primary itself retains native task and skill access. Applicable
user and project permission layers still apply.

## Influences

Selected debugging, codebase-design, prototyping, design-question, and skill-
authoring disciplines are adapted in original wording from ideas shared by
Matt Pocock. They refine the existing loops rather than add a competing
workflow. This repository remains MIT licensed.

Available logical invocations:

```text
build <request>
design <request>
analyze <question>
review <target>
pr-ready <target>
threat-model <scope>
wiki init|reinit|audit
```

Host syntax differs. Do not assume a slash command in Codex; use `$skill-name`
or native skill selection. Do not assume custom `/build` parity in Copilot;
use natural-language skill selection unless the installed CLI explicitly shows
the custom skill in its command surface.

## Models

Portable source and ordinary installation are model-neutral:

- Claude agents use `model: inherit`.
- OpenCode preserves its configured provider/model.
- Copilot preserves its selected model.
- Generated Codex agents omit model fields unless the user adds local
  overrides.

A clean global reset necessarily removes local model overrides. Reapply them
after installation if desired. The cost-aware Codex mapping used on the
maintainer's machine is:

| Role | Local Codex model |
|---|---|
| Main orchestrator | `gpt-5.6-sol`, medium; plan mode high |
| Repo Scout | `gpt-5.6-luna`, medium |
| Coder, Reviewer, Test Engineer | `gpt-5.6-terra`, medium |
| Browser QA, UI Critic | `gpt-5.6-terra`, medium |
| Diagnostician, Security Reviewer | `gpt-5.6-sol`, medium |
| Sage | `gpt-5.6-sol`, high |

These names are local/current Codex catalog identifiers, not portable public
provider promises. Installer updates preserve a clean model-only Codex agent
override while still refusing unrelated edits to managed agent files.

## Installation management

Environment overrides are respected:

```text
CODEX_HOME
CLAUDE_CONFIG_DIR
OPENCODE_CONFIG_DIR
OPENCODE_CONFIG
COPILOT_HOME
```

Verify the installed state:

```powershell
node cli/dist/kit.cjs doctor --host all --scope user
```

Before a clean reset, save host-specific model routing from Codex
`config.toml` and `agents/*.toml`, plus OpenCode `opencode.jsonc` and any
provider fallback configuration. A normal managed update preserves clean Codex
model-only overrides and does not own OpenCode fallback-plugin configuration.

Update without overwriting local conflicts:

```powershell
node cli/dist/kit.cjs update --host all --scope user --profile full `
  --security preserve --memory preserve
```

After an update or reset, compare the saved routing values, reapply any missing
host-local overrides, and run `doctor`. Portable repository prompts remain
model-neutral; routing stays a host configuration concern.

Uninstall removes only manifest-owned files, configuration keys, and managed
instruction blocks:

```powershell
node cli/dist/kit.cjs uninstall --host all --scope user
```

OpenCode and Copilot can also discover compatibility skill paths used by other
harnesses. Native copies take precedence by name; `kit doctor` reports every
duplicate so the state is visible. OpenCode users may set
`OPENCODE_DISABLE_CLAUDE_CODE_SKILLS=1` to suppress its Claude compatibility
copy.

## Verification and smoke testing

Repository validation:

```powershell
npm run typecheck --prefix cli
npm test --prefix cli
npm run validate --prefix cli
npm run check:drift --prefix cli
npm run bundle --prefix cli
```

Windows and macOS are release-blocking in CI. Both run the complete v6 suite,
generated drift validation, bundle generation, and an all-host project launcher
smoke test under a path containing spaces and non-ASCII text.

Create a disposable behavior fixture for a fresh harness session:

```powershell
.\scripts\create-smoke-project.ps1
```

```bash
bash scripts/create-smoke-project.sh
```

The generated `PROMPTS.md` first interrogates the installed orchestration
behavior, then requests a small implementation. This checks skill selection,
proportionate delegation, fresh tests, and avoidance of legacy memory files.

## Source layout

| Path | Purpose |
|---|---|
| `core/` | Canonical manifest, schemas, orchestrator, agents, and skills. |
| `packs/` | Optional UI specialists. |
| `adapters/` | Generated host-native artifacts. |
| `cli/` | Cross-platform renderer, installer, doctor, migration, wiki, and tests. |
| `scripts/` | Thin Windows and macOS launchers. |

## Security

Do not run the installer elevated against a directory writable by another
user. `permissive` removes ordinary Codex approval and sandbox protections; use
it only with repositories, credentials, machines, and networks you trust.

## License

MIT. See [LICENSE](./LICENSE).
