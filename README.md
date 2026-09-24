# Agentic Coding Kit v6.3

A native, development-focused workflow kit for long-horizon coding work in
Codex, Claude Code, OpenCode, Muse Code, and GitHub Copilot CLI. The active
harness session is the orchestrator. Skills define reusable loops; small,
bounded agents keep exploration, implementation, review, testing, and
specialist judgment out of the main context.

The kit is intentionally model-neutral. It does not force one provider's model
names into another harness.

## How it works

- One host-native primary orchestrator owns the outcome; specialists never
  become nested orchestrators or dispatch successors.
- The primary chooses a direct `INLINE` route where a skill permits it, or owns
  a delegated `LOOP`; specialists never choose the route or inherit ownership.
- Implementation loops share only a compact `GOAL`, numbered `ACCEPTANCE`, and
  repository-grounded `PLAN`, then use one Coder, fresh primary proof, one
  combined Reviewer, and at most two unsuccessful repairs for the same failure.
- Agent returns use only `Result`, `Evidence`, and optional `Next`.
- Extra test hardening, browser QA, UI critique, and security review are
  conditional evidence gates rather than ceremonial stages.
- Reviewer findings name file and line, what is wrong, the evidence, and the
  minimum fix; repair receives the finding verbatim plus owned files and
  checks to re-run.

## Start here

### Requirements

- Windows or macOS.
- Node.js 20 or newer.
- At least one supported harness installed separately.
- Git for project-scope installation and source inspection.

Build the management CLI once from the repository root (which itself has no
`package.json`):

```powershell
npm ci --prefix cli
npm run bundle --prefix cli
```

### Install

> **Warning: a user-scope install replaces the selected harness's complete
> global instructions, agents, skills, commands, and primary configuration.**
> Back up custom agents, skills, model settings, MCP servers, hooks, or
> permissions first. Use `--yes` only for deliberate non-interactive installs.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\install-all.ps1 `
  --scope user --profile core --security preserve --memory preserve
```

```bash
bash scripts/install-all.sh \
  --scope user --profile core --security preserve --memory preserve
```

For one harness use `install-codex`, `install-claude`, `install-opencode`,
`install-muse`, or `install-copilot` with the platform's `.ps1`/`.sh` suffix.
`core` installs every coding loop and all eight core agents; `full` adds
browser execution and visual UI critique. An all-host install dry-runs every
host before changing any of them.

## Skills

Nineteen lazy-loaded skills. The orchestrator loads only the one or two each
task needs; bodies are never preloaded.

| Skill | Purpose |
|---|---|
| `build` | Implement features, fixes, refactors, migrations, UI, API, data, and configuration. |
| `design` | Produce a feature, product, prototype, or UI design before implementation. |
| `grill` | Run an explicitly requested one-question-at-a-time decision interview. |
| `review` | Independent review of a diff, branch, contract, design, subsystem, or test delta. |
| `pr-ready` | Repair and package a diff for efficient human PR review. |
| `threat-model` | Read-only trust-boundary, attack-path, control, and mitigation analysis. |
| `wiki` | Initialize, reinitialize, or audit curated repository engineering knowledge. |
| `async` | Cancellation, retries, concurrent state, cleanup, and idempotency. |
| `backend` | Backend boundaries, persistence, failure behavior, and API contracts. |
| `components` | Find and compose existing UI primitives against their real APIs. |
| `debug` | Discriminate an unexplained failure or a repair that is not making progress. |
| `deslop` | Simplify an authorized diff with evidence while preserving safeguards. |
| `frontend` | Intentional UI: hierarchy, tokens, icons, states, and evidence. |
| `migrate` | Persisted-data, schema, or mixed-version rollout changes. |
| `perf` | A specified latency, throughput, or resource bottleneck. |
| `python` | Python behavior, typing, resources, and tests. |
| `security` | A named trust boundary, authorization rule, or cross-system contract. |
| `test` | Changed behavior through public seams. |
| `typescript` | TypeScript contracts, narrowing, and async behavior. |

Retired names (`analyze`, `architecture`, `experiment`) have no installed
skill. No agent is spawned for ceremony: a Repo Scout, Test Engineer,
Architect, Diagnostician, Sage, Security Reviewer, Browser QA, or UI Critic
joins only for a concrete discovery need, risk, or proof gap.

## Agents

| Agent | Responsibility | Writes |
|---|---|---|
| `architect` | Architecture and change-boundary decisions. | No |
| `repo-scout` | Bounded repository discovery and evidence mapping. | No |
| `coder` | Production implementation and durable behavior evidence. | Production and tests |
| `reviewer` | Independent code, design, and test-delta judgment. | No |
| `simple-reviewer` | Conditional PR-ready file-unit review for broad diffs; never the final gate. | No |
| `test-engineer` | Independent high-value test hardening. | Tests and fixtures only |
| `diagnostician` | Repeated or ambiguous failures. | No |
| `sage` | Principal-engineering challenge for difficult decisions. | No |
| `security-reviewer` | Material trust-boundary changes. | No |

`full` adds `browser-qa` and `ui-critic`. Every agent returns to the primary;
completed specialists are never reactivated and transcripts are not forwarded.

## Harness locations and invocation

| Harness | User agents | User skills | Typical invocation |
|---|---|---|---|
| Codex | `~/.codex/agents/*.toml` | `~/.agents/skills/<name>/SKILL.md` | `$build ...`, `$review ...` |
| Claude Code | `~/.claude/agents/*.md` | `~/.claude/skills/<name>/SKILL.md` | `/build ...`, `/review ...` |
| OpenCode | `~/.config/opencode/agents/*.md` | `~/.config/opencode/skills/<name>/SKILL.md` | `/build ...` thin command or native skill |
| Muse Code | `~/.config/muse/agents/*.md` | `~/.config/muse/skills/<name>/SKILL.md` | Natural language; skills discovered natively |
| Copilot CLI | `~/.copilot/agents/*.agent.md` | `~/.copilot/skills/<name>/SKILL.md` | Natural language; `/skills` and `/agent` to inspect |

Verify the installed state with `node cli/dist/kit.cjs doctor --host all
--scope user`. Uninstall removes only manifest-owned files, keys, and managed
blocks: `node cli/dist/kit.cjs uninstall --host all --scope user`.

## Repository wiki

`wiki init` / `reinit` / `audit` build a source-backed map of how a repository
actually works (entry points, flows, boundaries, conventions, tests). Normal
work never edits `.wiki`; only explicit `wiki init` or `wiki reinit` may.

## Verification

```powershell
npm run typecheck --prefix cli
npm test --prefix cli
npm run validate --prefix cli
npm run check:drift --prefix cli
```

## Source layout

| Path | Purpose |
|---|---|
| `core/` | Canonical manifest, schemas, orchestrator, agents, and skills. |
| `packs/` | Canonical optional specialist sources. |
| `adapters/` | Generated host-native artifacts; edit canonical sources instead. |
| `cli/` | Renderer, installer, doctor, migration, wiki, and tests. |
| `scripts/` | Thin Windows and macOS launchers. |

## Security

Do not run the installer elevated against a directory writable by another
user. `permissive` removes ordinary approval and sandbox protections; use it
only with repositories, credentials, machines, and networks you trust.

## License

MIT. See [LICENSE](./LICENSE).
