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
│  ║  ├── skills/      24 cross-CLI skills (build/review/swarm…)  ║  │
│  ║  ├── tools/       23 PS scripts (classifiers, gates, hooks)  ║  │
│  ║  ├── workflows/   gstack / superpowers / caspar plugins      ║  │
│  ║  ├── context/     protocols, skill-memory-index              ║  │
│  ║  └── session-state/<id>/  per-session gates + handoffs       ║  │
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
`.github/copilot-instructions.md`, `.kilocode/rules/`). Rather than fork the
kit per CLI, the kit's logic lives in `~/.agents/` once, and a thin **adapter**
per CLI writes a tiny include-marker into that CLI's home config pointing back
at the shared content. Switch CLIs at any time — the workflows, gates, memory,
and self-improvement loop are identical.

## Requirements

- **PowerShell 7+ (`pwsh`)** — the runtime tools are designed for pwsh. Windows PowerShell 5.1 will fail on UTF-8 emoji glyphs in the scripts. Install via `winget install Microsoft.PowerShell` or https://aka.ms/PSWindows.
- **Python 3.10+** with `playwright` + `pyyaml` — only if you use `/redesign` or `playwright-explorer`. Skip if you don't need UI screenshot capture.
  ```
  pip install playwright pyyaml && python -m playwright install chromium
  ```
- **Mac/Linux**: `pwsh` works natively. Use `scripts/install.sh` if you prefer bash for the installer step itself.

## Install

### Quick start — pick the CLI you use, run one command

```powershell
# Use Claude Code
pwsh ./scripts/install.ps1 -For claude

# Use OpenCode
pwsh ./scripts/install.ps1 -For opencode

# Use Codex CLI
pwsh ./scripts/install.ps1 -For codex

# Use multiple
pwsh ./scripts/install.ps1 -For "claude,opencode"

# Or install for every CLI that has a meaningful device-wide config
# (Claude, Codex, OpenCode, plus a generic ~/AGENTS.md for Aider/Cline/Cursor/etc.)
pwsh ./scripts/install.ps1 -For all

# Or auto-detect what's on your PATH and install for those
pwsh ./scripts/install.ps1 -Auto
```

Each `-For <cli>` does three things:

1. **Populates `~/.agents/`** with skills, tools, protocols, and the workflow plugins skills reference (gstack / superpowers / caspar-workflows). Renders `skill-memory-index.json` with absolute paths.
2. **Writes the kit instructions companion** to that CLI's config dir (e.g. `~/.claude/agentic-kit.md`, `~/.config/opencode/agentic-kit.md`, `~/.codex/agentic-kit.md`, or `~/.agentic-kit/AGENTS.md` for the generic case).
3. **Wires lifecycle automation** — for Claude Code merges hooks into `~/.claude/settings.json`; for OpenCode installs the plugin at `~/.config/opencode/plugins/agentic-kit.ts`; for Copilot the lifecycle is baked into the per-repo instructions file.

**A note on `copilot` and `kilocode`:** these tools have no useful device-wide
config — Copilot only reads `.github/copilot-instructions.md` from each
workspace, and Kilo Code only reads `.kilocode/rules/*.md` from each workspace.
Passing `-For copilot` or `-For kilocode` prints a one-line message pointing
you at the per-repo install instead. `-For all` therefore expands to
`claude, codex, opencode, generic`.

Pre-flight runs `validate-bundle.ps1` and refuses to install a broken kit (override with `-Force`).

After install, restart your CLI. Verify with:

```powershell
pwsh ./scripts/doctor.ps1   # 17-check health report
```

### Per-repo bootstrap (advanced — usually you don't need this)

If you want the kit's repo-template (`.kit/context/`, `.kit/workflows/`, `.wiki/`) dropped into a specific repo:

```powershell
pwsh ./scripts/install.ps1 -TargetRepo /path/to/repo -InstallRepoTemplate -InstallAdapter claude
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
| **Copilot CLI** | `.github/copilot-instructions.md` | ✅ Lifecycle baked into instructions — agent calls `pre-session.ps1` at start of `/build`, `post-session.ps1` at end (no native hooks) |
| **Codex CLI** | `AGENTS.md` | Manual — Codex hook surface varies by version, no fabricated config shipped |
| **Kilo Code** | `AGENTS.md` + `.kilocode/rules/*.md` (5 modes) | Manual or via VSCode tasks.json |
| **Generic** | `AGENTS.md` (canonical for Aider, Cline, Cursor, Continue, etc.) | Manual |

## Core operating model

### Six workflow commands + two swarm-eligible

| Command | What it does | Swarm? |
|---|---|---|
| `/plan` | clarify scope, map files, trace blast radius, stop for approval | sequential |
| `/build` | execute approved plan with freshness check + implement → review → verify gates | sequential (parallel-reviewers OK at FULL tier) |
| `/review` | hierarchical: surface → interactions → synthesis → adversarial → false-positive verifier | sequential, optional `swarm-review` (parallel reviewers, sequential implementer) |
| `/analyze` | multi-angle research/synthesis | sequential |
| `/investigate` | hypothesis-driven root-cause debugging | sequential |
| `/refactor` | principle-driven restructuring with consequence tracing | sequential |
| `/redesign` | greenfield UI / multi-component visual rebuild | **swarm-eligible** — fan out one `design-driver` per screen |
| `/security-review` | adversarial audit by attack class | **swarm-eligible** — fan out one agent per attack class |

### Autonomy: 3-axis classification

The system chooses behavior automatically:

```
Scope:  ISOLATED  /  SHARED  /  CRITICAL          (how dangerous?)
Tier:   INLINE  /  TARGETED  /  FULL  /  SWARM    (how much ceremony?)
Mode:   sequential  /  swarm-review  /  swarm-fanout  (how to execute?)
```

`scope-classifier.ps1` picks scope from changed files. `pre-session.ps1` recommends a tier from scope + file count. `swarm-classifier.ps1` decides mode from verb + scope + opt-in.

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
| `SESSION-ONLY` | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` | Task progress, scratch, session-private notes |

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
| `bundle/global/.agents/tools/` | 23 PowerShell tools + 1 Python — classifiers, hooks, resolvers, runner, validator, **test-loop, edit-with-lint, detect-slop, compress-memory, harness-propose, harness-review, auto-consolidate, reflect-trigger** |
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

# ... agent does the work, marks gates as it goes:
$ pwsh ~/.agents/tools/state-gate.ps1 -SessionId <id> -Mark "context_loaded"
$ pwsh ~/.agents/tools/state-gate.ps1 -SessionId <id> -Mark "implementation_done"
$ pwsh ~/.agents/tools/state-gate.ps1 -SessionId <id> -Mark "verification_evidence"

$ pwsh ~/.agents/tools/post-session.ps1 -SessionId <id>
  Gate Status (scope: SHARED): all required gates passed
  Auto-consolidating reflections...
  auto-consolidated: 7 -> 2 (deduped=3 archived=1 stale=1 promoted=0)
  Session registered. Handoff: ~/.agents/session-state/<id>/handoffs.md
```

Under Claude Code or OpenCode, `pre-session` and `post-session` fire automatically via hooks/plugin. Under Copilot CLI, the agent calls them itself per the baked instructions. Under Codex CLI / Kilo Code / generic, run them manually.

## Important honesty

This kit is **pre-v1**. What that means in practice:

- **End-to-end runs are mostly unverified at scale.** The pieces work in isolation (validator + Pester + smoke tests all pass). Full multi-session usage across many repos hasn't been recorded. Test on a throwaway repo first.
- **Hook event names are best-effort verified against current docs.** Claude Code uses `${CLAUDE_SESSION_ID}`; OpenCode uses `session.created` / `session.deleted` event-handler keys (re-verified against opencode.ai/docs/plugins). If hooks don't fire, that's where to look.
- **Upgrade safety is via backup-and-replace.** `install.ps1 -Upgrade` moves `~/.agents/` to a timestamped backup before installing. Hand-merge customizations afterward. A proper override pattern (`~/.agents/overrides/{skill}.md`) isn't implemented yet.
- **CI is included but not yet exercised by external contributions.** `.github/workflows/validate.yml` runs validate-bundle + Pester on push and PR.

The kit is **opinionated by design**: hardcoded layout, explicit session artifacts, explicit write-routing, explicit review/build/plan lanes. It is not a zero-assumption framework. It is a disciplined operating system for serious coding work, and it asks you to follow its conventions in exchange for the loop closing automatically.

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

- Currently AI Engineer at **Bentley Systems** (Dublin).
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
