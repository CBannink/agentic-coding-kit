# Agentic Coding Kit v6

A native, development-focused workflow kit for long-horizon coding work in
Codex, Claude Code, OpenCode, and GitHub Copilot CLI. The active harness session
is the orchestrator. Skills define reusable loops; small, bounded agents keep
exploration, implementation, review, testing, and specialist judgment out of
the main context.

The kit is intentionally model-neutral. It does not force one provider's model
names into another harness.

## Start here

### Requirements

- Windows or macOS.
- Node.js 20 or newer. The current release is a bundled JavaScript CLI, not a
  standalone native executable.
- At least one supported harness installed separately: `codex`, `claude`,
  `opencode`, or `copilot`.
- Git for project-scope installation and wiki initialization.

Build the management CLI once from the repository root:

```powershell
npm ci --prefix cli
npm run bundle --prefix cli
```

On macOS, use the same commands in Terminal.

### Safe install: preserve existing configuration

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

`core` installs every coding loop and all seven core agents. Use `full` only
when browser execution and visual UI critique are useful.

### Destructive clean install

> **Warning: `--clear-global-config --yes` backs up and then removes the
> selected harness's global instructions, agents, skills, commands, and primary
> settings/configuration file.** This includes hand-written agents, MCP/provider
> configuration, hooks, model choices, and permission settings stored there.
> Authentication databases and opaque application state are not intentionally
> removed.

Backups are written under:

```text
~/.agentic-kit-backup/<timestamp>/<host>/
```

Example clean install on this machine, with Codex explicitly configured for
unrestricted local execution:

```powershell
.\scripts\install-all.ps1 --scope user --profile full `
  --security permissive --memory preserve `
  --clear-global-config --yes
```

On macOS:

```bash
bash scripts/install-all.sh --scope user --profile full \
  --security permissive --memory preserve \
  --clear-global-config --yes
```

`permissive` currently emits a validated Codex configuration with
`approval_policy = "never"` and `sandbox_mode = "danger-full-access"`. Other
harnesses retain their native permission semantics; the kit does not invent
unsupported parity fields.

An all-host install performs a complete dry-run preflight before changing any
host. Files are then installed sequentially. Backups are the recovery path for
an operating-system failure during the mutation phase.

## What gets installed

### Seven core skills

| Skill | Purpose |
|---|---|
| `build` | Implement features, fixes, refactors, migrations, UI, API, data, configuration, and code-linked documentation. |
| `design` | Produce a feature, architecture, or UI design before implementation. |
| `analyze` | Read-only diagnosis, explanation, comparison, architecture, dependency, and performance analysis. |
| `review` | Independent review of a diff, branch, contract, design, subsystem, or test delta. |
| `pr-ready` | Repair and package a diff for efficient human PR review. |
| `threat-model` | Read-only trust-boundary, attack-path, control, and mitigation analysis. |
| `wiki` | Initialize, reinitialize, or audit curated repository engineering knowledge. |

These are general development workflows. They are not seven mandatory stages.
The orchestrator chooses the smallest useful loop and may work inline for a
clear, low-risk change.

### Adaptive coding loops

- `INLINE`: direct work for a clear, tightly bounded change. No ceremonial
  agent spawning.
- `STANDARD`: targeted implementation with proportionate checks and independent
  review or testing where it adds real value.
- `DEEP`: explicit contract, focused discovery, independent implementation
  review and test hardening, plus conditional UI/security evidence.

The routes are prompt policy, not a rigid TypeScript workflow engine. Code
enforces deterministic concerns such as safe installation, schema parsing,
managed ownership, evidence files, and bounded retries. The main model decides
which useful route comes next and when the requested outcome is sufficiently
proven.

Design uses `INLINE DESIGN` or `REVIEWED DESIGN`. PR preparation uses
`INLINE`, `STANDARD`, or `DEEP`. Threat modeling uses `FOCUSED`, `FULL`, or
`INCREMENTAL`. Failed coder/reviewer/test repair cycles stop after two
unsuccessful rounds and return evidence to the user.

### Seven core agents

| Agent | Responsibility | Writes |
|---|---|---|
| `repo-scout` | Bounded repository discovery and evidence mapping. | No |
| `coder` | Coherent production implementation and minimum behavior tests. | Production and tests |
| `reviewer` | Independent code, design, and test-delta judgment. | No |
| `test-engineer` | Independent high-value test hardening. | Tests and fixtures only |
| `diagnostician` | Discriminate repeated or ambiguous failures. | No |
| `sage` | Rare principal-engineering challenge for difficult decisions. | No |
| `security-reviewer` | Concrete review of material trust-boundary changes. | No |

The `full` profile additionally installs:

- `browser-qa`: browser execution and evidence capture.
- `ui-critic`: independent visual and UX critique.

All handoffs return to the main orchestrator. Agents never dispatch their own
successor. The orchestrator sends a bounded assignment and forwards only the
facts needed by the next role, rather than copying transcripts.

## Repository wiki

`wiki init` and `wiki reinit` build an architect-grade map of how the repository
actually works: entry points, control/data flow, module boundaries, APIs,
authentication, IPC, integrations, jobs, error/configuration conventions,
tests, CI, release practice, and workspace-specific differences where present.

The required pages are:

```text
.wiki/index.md
.wiki/repository-map.md
.wiki/architecture.md
.wiki/engineering.md
```

Initialization uses deterministic inventory, one Orientation Scout, one to
three targeted evidence scans, orchestrator synthesis, independent review, and
a parser-backed writer/audit. Normal build sessions never update the wiki.

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
`.github/agents` plus `.github/skills` respectively. Codex/OpenCode/Copilot
share one managed root `AGENTS.md` block; Claude uses one managed `CLAUDE.md`
location.

Available logical invocations:

```text
build <request>
build --test-first <request>
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
| Main orchestrator | `gpt-5.6-terra`, medium |
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

Update without overwriting local conflicts:

```powershell
node cli/dist/kit.cjs update --host all --scope user
```

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
