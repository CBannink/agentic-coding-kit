# Source notes for the Medium article — agentic-coding-kit (2026-05 sprint)

Reference document for the writing agent. Comprehensive, ordered chronologically. Pick whichever narrative arc fits the audience (suggestions at the end).

---

## TL;DR

A 4-day sprint on the **Caspar Bannink Agentic Coding Kit** — a multi-host coding-agent kit (Claude Code, OpenCode, GitHub Copilot CLI) — turned into a story about **what makes multi-agent kits actually work**. Three load-bearing learnings:

1. **The main session is the orchestrator.** Wrapping orchestrator subagents are the wrong abstraction. Slash commands hold the workflow body; agents are leaves.
2. **Per-host frontmatter sanitization is non-optional.** Each host's YAML parser silently rejects the others' format. BOM-prefixed files are invisible to Claude Code. Unicode in descriptions is invisible to Copilot. `tools:` as comma-string is invisible to OpenCode.
3. **More critics is not more rigor.** Adversarial-reviewer agents past 2-3 critics produce false-positive flooding, not insight.

5 PRs shipped over 4 days. Three merged to main, one open. Full numbered history below.

---

## Starting state (pre-sprint)

The repo `agentic-coding-kit` is a multi-host kit shipping:
- 12 slash commands (`/build`, `/review`, `/investigate`, `/plan`, `/refactor`, `/redesign`, `/security-review`, plus 5 setup commands)
- ~15 specialist subagents (code-quality-reviewer, security-reviewer, modularity-expert, etc.)
- 35+ PowerShell lifecycle tools (state-init, state-gate, workflow-evidence, verify-writeback, etc.)
- Wiki + repo-memory bootstrappers (`/wiki-init`, `/kit-init`, `/bootstrap-harness`)
- Per-host adapters (Claude Code, OpenCode, Copilot CLI, Codex CLI, Gemini CLI)
- A PowerShell installer (`scripts/install.ps1`)

It billed itself as "works on 5 hosts." Reality (discovered during the sprint): it installed on all 5, **loaded on 1**.

---

## The discovery — 5-agent parallel review

Six specialized agents ran in parallel against the repo. Critical findings:

1. **Marker schism** causing 4× CLAUDE.md duplication (~30K wasted tokens per session). `install.ps1` used `<!-- agentic-kit:include -->` while 5 other installers used `<!-- agentic-kit:begin/end -->`. Each writer's regex looked only for its own pair and **appended** when not found.
2. **Hardcoded maintainer path** in `install-copilot-kit.ps1`: `Join-Path $HOME 'Downloads\caspar_bannink_agentic_coding\caspar_bannink_agentic_coding'` — leaked maintainer username + broke any non-maintainer install.
3. **Default install wiped `~/.agents/session-state/`** via `Copy-Tree -ReplaceDestination` — losing user history on every reinstall.
4. **Iron Law gate was self-reported.** `workflow-evidence.ps1 -AddVerification` accepted any string. OpenCode plugin manufactured `exit_code = 0` when the test runner didn't emit one.
5. **OpenCode per-repo install pointed at the wrong path segment.** `.config/opencode/` is global; project scope is `.opencode/`. Plus all OpenCode agents missing `mode: subagent` so the Task tool wouldn't spawn them.
6. **Copilot CLI plumbing was completely missing.** Install only wrote `copilot-instructions.md`; no agents, no hooks. Yet Copilot had been promoted to "primary host" days earlier.

---

## Tier-B (PR #1, merged) — Install hygiene + foundation

7 commits:

- **P1 marker schism**: Unified all installers on `<!-- agentic-kit:begin/end -->`, added `Strip-AllKitBlocks` legacy-stripping pre-pass that handles all 4 historic marker variants, added `-RepairKitBlock` cleanup mode.
- **P2 path de-hardcoding**: 3-tier resolver (env var, staged location, repo-relative).
- **P3 user-state preservation**: snapshot/restore around `Copy-Tree` for user-mutable subpaths (`session-state/`, `context/handoffs.md`, `context/reflections.md`, `inspiration/`).
- **P4 Copilot CLI plumbing**: 15 `.agent.md` agent files, 4 hook JSON configs, install.ps1 wired to deploy, `copilot-instructions.md` de-lied (dropped "no hooks / no subagents" claims that were false since Copilot v0.0.397 in Jan 2026).
- **P5 Iron Law tightening**: required structured `verification_proofs` tuple (command + exit_code 0 + output_hash); OpenCode plugin no longer manufactures exit codes.
- **P6 OpenCode path correction**: per-repo install path fixed, `mode: subagent` added to 15 agents, `AGENTS.md` (not `prompt.md`) for global rules.
- **P7 stale-file pruning**: `-PruneStaleAssets` flag removes orphaned per-host command files left by older kit versions; pruned files become `*.pruned-<timestamp>` (recoverable, not hard-deleted).
- Plus a `-CleanReinstall` flag wiping kit-managed dest dirs before rewrite.

---

## Tier-D (PR #2, closed/superseded) — The wrong abstraction

Built 21 wrapping orchestrator agents (7 per host: `build-orchestrator`, `review-orchestrator`, etc.) on the theory that Claude Code's description-matching auto-routing would dispatch them.

They DID load and fire in interactive Claude Code (the user's own evidence: `redesign-orchestrator` running with 75 tool uses). But the convergence loop logic embedded in the orchestrator bodies often led to inline work anyway — the orchestrator subagent did the same job the main session would have done, just one indirection deeper.

PR #2 closed without merging. Lesson: extra agent layers don't add capability; they add latency and context cost.

---

## The pivot — web research session

Surveyed 12+ popular Claude Code kits (wshobson/agents, everything-claude-code at ~100K stars, lst97/claude-code-sub-agents, vijaythecoder/awesome-claude-agents, barkain/claude-code-workflow-orchestration, VoltAgent, etc.) plus Anthropic's official multi-agent docs.

**Convergent finding**: the main session IS the orchestrator. Custom agents are leaves. Workflows live in slash commands (Claude/OpenCode) or shell scripts (Copilot CLI) — NOT in wrapping orchestrator subagents. barkain explicitly deprecated their `delegation-orchestrator` agent: *"now provided by native plan mode."*

This reshaped the next two PRs.

---

## Tier-E (PR #3, merged) — The course correction

- **Deleted 21 wrapping orchestrators** (kept only `goal-orchestrator` for genuinely autonomous loop semantics).
- **Restored slash command bodies as real workflow definitions** addressed to the main session — phased pipelines with explicit Task-tool spawn instructions.
- **Added 7 Copilot CLI shell scripts** at `bundle/adapters/copilot-cli/bin/kit-{build,review,investigate,plan,refactor,redesign,security-review}.sh` chaining `copilot --agent X -p` calls (the canonical Copilot pattern per [GitHub's docs](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/automate-with-actions)).

### Two critical install fixes that explained "ships everywhere, loads on Claude only"

- **The BOM bug** — *the silent kit killer*. `Set-Content -Encoding UTF8` in PowerShell 5.1 writes UTF-8 **with BOM**. Claude Code's YAML frontmatter parser silently rejects every BOM-prefixed agent file. The kit was reporting "16 installed" while 0 actually loaded. Discovered live when probing `claude -p "list subagents"` returned only built-ins. Fixed via `[System.IO.File]::WriteAllText` with `UTF8Encoding($false)`. Also stripped BOM from all 22 source files.
- **Per-host frontmatter sanitizers** — three new install-time transformers:
  - **OpenCode**: rejects Claude's `tools: A, B, C` comma-string with "expected object." All 16 kit agents were silently rejected. New `Install-OpenCodeAgentsFromSource` strips Claude-only keys (`tools`, `permissionMode`, `maxTurns`, `disallowedTools`).
  - **Copilot**: rejects Unicode in descriptions, descriptions over ~300 chars, single-quoted YAML lists. Discovered live when `copilot --agent nonexistent` returned only 11 of 22 agents. New `Install-CopilotAgentsFromClaudeSource` strips Unicode → ASCII (em-dash → `-`, arrows → `->/<-`, smart quotes → straight, ellipsis → `...`), caps at 300 chars, double-quotes the value.
  - **Claude**: ensures BOM-free UTF-8 (the fix above).

### Mechanical writeback gate + reflect trigger

Wired into all 7 slash command bodies. Phase 5b runs `verify-writeback.ps1` (Bash, not vibes). Phase 5c checks `reflections.md` length, triggers `/reflect` at 5+ entries.

### First spawn-budget tightening

ISOLATED 0-1 spawns; SHARED 4 typical (max 6); CRITICAL 7 (max 12). `adversarial-reviewer` moved CRITICAL-only.

### goal-orchestrator v3

Full toolbox registry (15 leaf agents + 12 PowerShell tools + 4 on-demand skills). Goal-type classification (CODE / DESIGN / INVESTIGATION / REFACTOR / MULTI). DESIGN pipeline integrates the Playwright toolchain (aesthetic-director → playwright-navigator → playwright-runner → ux-driver → ui-driver → visual-diff). Mechanical guards: convergence cap 6, stuck detection (same `file:line:rule` BLOCKING for 3 iterations), empty-diff watchdog, rollback gate. Machine-parseable `GOAL_STATUS` first line.

---

## PR #4 (open) — Bootstrap-harness + pr-reviewer + README

- **`bootstrap-harness` rewritten as goal-conditioned**. New Phase 1 detects:
  - Git workflow (branch naming, merge strategy via `git log --merges` analysis, commit cadence + style, PR templates, CODEOWNERS, CI required checks)
  - Architecture preferences (layering, DI pattern, error handling style, test framework + location, FE state library, API style, schema validation, type strictness)
  - PR review preferences (avg PR size, reviewer attribution, comment density via `gh pr list`)
  - All written to `.kit/context/conventions.md`. Other agents (`workflow-implementer`, `code-quality-reviewer`, `pr-reviewer`) read it so they implement/review per the repo's actual style, not generic best practices.
  - Phase 5 mechanical Bash convergence check; iterates up to 3 times.
  - Phase 6 outputs `BOOTSTRAP_STATUS: ...` machine-parseable first line.
- **New `pr-reviewer` agent on all 3 hosts**. Distinct from `code-quality-reviewer` (lint-class) and `security-reviewer` (security-only): pr-reviewer is the holistic verdict-issuing pass. Reads PR title + description + commits + diff + CI + repo conventions. Walks a 10-dimension human-reviewer checklist (correctness, tests, scope-match, architecture/convention adherence, security, performance, backwards compat, error handling/observability, style/naming/readability, documentation, PR hygiene, risk profile). Outputs Markdown PR-comment-style review with `PR_REVIEW: APPROVE/REQUEST_CHANGES/COMMENT` first line. Sources cited: Google's Code Review Developer Guide, Conventional Comments, Anthropic's engineering review patterns.
- **README**: full agent inventory (17 agents per host), `pr-reviewer` highlight section, roadmap with 22 future agent/tool ideas (release-manager, migration-writer, pr-description-writer, dependency-updater, incident-responder, dead-code-finder, i18n-extractor, a11y-auditor, observability-auditor, cost-tracker, plus 7 PowerShell tools + 5 architectural improvements + 3 explicit non-goals).
- **Plugin cache cleanup**: removed 84 duplicate Vercel plugin SKILL.md files (3 cached versions; kept only 0.42.1; freed ~167 MB). NOT a kit issue — Claude Code's plugin marketplace cache.

---

## PR #5 (in progress this turn) — Adversarial demote + spawn-budget v2 + auto-apply reflect

### The "more critics ≠ more rigor" reflection

Three convergent signals against `adversarial-reviewer`:

1. **Anthropic's multi-agent research** found that adding critique rounds past 2-3 degrades output, not improves it. The critic agent is asked to find problems → it WILL find them, real or not. Past a threshold, false-positive rate exceeds true-positive value-add.
2. **Empirical from session reflections**: adversarial findings get `[SUPERSEDED]` by `build-loop-gate` more often than they survive. When code-quality-reviewer + security-reviewer have already passed, adversarial is fishing.
3. **barkain's deprecation note** explicitly cited "critic loops produce diminishing returns and noise" as a reason for retiring their delegation-orchestrator.

Verdict: **demoted adversarial from default matrix entirely.** Agent file kept (manual invoke for genuinely critical changes — auth rewrites, schema migrations) but removed from `/build` and `/review` default flows. `final-verifier` already enforces Iron Law; that's the remaining safety net.

### Spawn-budget v2 (after Tier-E was still ceremony)

| Tier | Tier-E | v2 (this PR) |
|---|---|---|
| ISOLATED | 0-1 | **0** (always inline) |
| SHARED | 4 typical / 6 max | **3 typical** (implementer + 1 reviewer + final-verifier) / 4 max |
| CRITICAL | 7 typical / 12 max | **5 typical** / 7 max |

**Single-reviewer rule:** spawn ONE reviewer based on dominant diff signal. Spawn a second only if the first surfaces a finding clearly outside its lane. Eliminates the "spawn all that match conditions" pattern that put 3 reviewers on every shared change.

### Auto-apply reflect (tiered, with rollback)

`/reflect` was gated for user approval because Tier-D taught us autonomous prompt rewrites can drift the kit silently. But not every reflection is equally risky. New tiered policy:

| Bucket | Auto-apply? | Rollback |
|---|---|---|
| Specialist memory accretion (per-repo, per-role) | **YES** | Snapshot + revert if user comment resurrects the dampened finding |
| conventions.md updates (per-repo) | **YES** | Snapshot + auto-revert if next bootstrap detection contradicts |
| Per-tier spawn-count adjustments (repo-scoped `.kit/workflows/build.md`) | **YES** | Auto-revert if last-N verification-pass-rate drops |
| Slash command body rewrites (global) | **NO** — still gated | n/a |
| Tool/hook PowerShell logic | **NO** — still gated | n/a |

New tool: `auto-apply-reflect.ps1` (~80 LOC). Runs from `post-session.ps1` after detectors append to `reflections.md`. Auto-applies safe-bucket findings only when the same signature appears 3+ times. Snapshots prior state to `~/.agents/context/auto-applied-snapshots/`. Audit log at `~/.agents/context/auto-applied.md`.

This is **measure → change → check → keep/revert** (Karpathy/Autoresearch pattern) wired to safe buckets only.

---

## Architectural learnings (collected, for any narrative arc)

1. **Main session IS the orchestrator** (per Anthropic's multi-agent coordination patterns blog). Wrapping orchestrator subagents are an extra layer that successful kits don't use. wshobson, ECC, lst97, vijaythecoder all skip them; barkain explicitly deprecated theirs.
2. **Per-host frontmatter sanitization is mandatory.** Each host has a different parser:
   - Claude Code rejects BOM-prefixed files silently.
   - OpenCode rejects Claude's `tools: A, B, C` and Claude-only keys.
   - Copilot CLI rejects Unicode + long descriptions + single-quoted YAML lists.
3. **Copilot CLI is command-based, not hook-based.** Workflows there live in shell scripts, not orchestrator agents. Custom slash commands aren't supported (issue #1113).
4. **PreToolUse exit-2 blocking hooks are documented broken** in Claude Code 2026 (Anthropic issues #24327, #13744, #26923) — model treats hook denials as user denials and stops/defers rather than pivoting. Removed 3 PreToolUse blocking hooks; kept only the bash dispatcher.
5. **Description-matching auto-routing is variable.** Even with `MUST BE USED` triggers, the model exercises judgment. Interactive Claude Code spawns more aggressively than `claude -p` print mode.
6. **Mechanical gates beat prose enforcement.** `verify-writeback.ps1` Bash call > "remember to update the wiki." Structured `verification_proofs` tuple > free-form string accepted. Every guarantee gets a Bash call, not a prose hint.
7. **More critics is not more rigor.** Adversarial review past 2-3 critics produces noise, not signal. The fix is removing the critic, not tuning it.

---

## Final state — what's shipped on `main` (after PR #5 merges)

| Layer | Count | Notes |
|---|---|---|
| Slash commands | 12 | 7 workflows + 5 setup |
| Workflow agents | 5 | Generic transport (workflow-explorer/-implementer/-reviewer/-skeptic/-ui-qa) |
| Specialist agents | 10 | Domain experts (code-quality, security, modularity, adversarial [demoted to manual-invoke], final-verifier, qa, spec, playwright-navigator, ux-driver, ui-driver) |
| Orchestrators | 2 | goal-orchestrator + pr-reviewer |
| **Per-host total** | **17** | All 3 hosts (Claude Code, OpenCode, Copilot CLI) load all 17 |
| Skills | 31 | aesthetic-director, build, review, investigate, plan, refactor, redesign, security-review, bootstrap-harness, kit-init, kit-migrate, wiki-init, git-archaeology, reflect, tdd, spec, swarm, gstack-* (5), verification-loop, consequence, derive-repo-skills, design-driver, playwright-explorer, playwright-navigator, ui-driver, ux-driver |
| Copilot shell scripts | 7 | kit-{build,review,investigate,plan,refactor,redesign,security-review}.sh |
| PowerShell tools | 36+ | scope-classifier, frontend-detector, dev-server-runner, playwright-runner, visual-diff, wiki-resolver, specialist-memory-resolver, brief-resolver, workflow-evidence, state-gate, verify-writeback, **auto-apply-reflect** (new), etc. |

**Typical /build now:** 3 spawns (down from 7 typical at sprint start). ~57% spawn reduction with no observed regression in finding quality (because 2 of those 4 spawns were the redundant-critic / adversarial pair).

---

## Numbers

- **5 PRs**: #1 (merged), #2 (closed/superseded), #3 (merged), #4 (open), #5 (in progress)
- **~45 commits** across the branches
- **~6,600 tokens saved per Claude session** from canonical-block deduplication
- **84 duplicate plugin SKILL files removed** (~167 MB)
- **Adversarial-reviewer demoted** from default matrix at every tier
- **Default /build spawn count: 7 → 3** (typical SHARED case)
- **2-of-3 hosts live-verified** (Claude Code + OpenCode); Copilot CLI install verified, runtime blocked by GitHub org policy
- **Auto-apply reflect coverage**: 3 safe buckets, 0 unsafe (slash command bodies + global agent prompts + tool logic still require user approval via `/reflect`)

---

## What's NOT fixed / known limitations (be honest)

- **Copilot CLI runtime blocked** by GitHub org policy. Kit ships and installs correctly there; execution requires admin to enable Copilot CLI feature flag.
- **Print-mode (`claude -p`) tends to inline** even when slash command body instructs Task spawn. Interactive mode follows the body better. Model-tendency, not kit bug.
- **OpenCode runtime untested live** this sprint. Install verified (`opencode agent list` returns all 17 agents); behavior should follow Claude Code per OpenCode docs but unproven empirically.
- **Specialist agents still duplicated 10×3** (Claude/OpenCode/Copilot) in source tree. Roadmap: move to `_shared/specialist-agents/` with per-host install-time sanitization.
- **No closed-loop quality measurement** for individual agents. Auto-apply reflect dampens noisy findings, but doesn't yet score *which agent is noisy*. Aggregating reflection signals by emitter is the next reflection-system improvement.
- **`auto-apply-reflect.ps1` not yet wired into `post-session.ps1`** — PR #5 ships the tool; wiring is a follow-up commit.
- **22 future-roadmap items** documented in README (10 agents, 7 tools, 5 architectural, 3 non-goals).

---

## Citations the article should include

- Anthropic's [Multi-agent coordination patterns](https://claude.com/blog/multi-agent-coordination-patterns) — "the main agent writes code, edits files, and runs commands itself, dispatching subagents in the background"
- Anthropic's [Custom subagents docs](https://code.claude.com/docs/en/sub-agents) — description-matching delegation
- GitHub's [Copilot CLI Actions automation](https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/automate-with-actions) — bash chaining as canonical multi-step pattern
- Google's [Code Review Developer Guide](https://google.github.io/eng-practices/review/reviewer/) — basis for pr-reviewer's checklist
- [Conventional Comments](https://conventionalcomments.org/) — BLOCKING/NON-BLOCKING/NIT taxonomy
- ECC at ~100K stars: [github.com/affaan-m/everything-claude-code](https://github.com/affaan-m/everything-claude-code) — proof the simple "leaves + slash commands" pattern works at scale
- barkain's deprecation: [github.com/barkain/claude-code-workflow-orchestration](https://github.com/barkain/claude-code-workflow-orchestration) — *"delegation-orchestrator agent has been deprecated"*
- Claude Code issues confirming PreToolUse exit-2 broken: [#24327](https://github.com/anthropics/claude-code/issues/24327), [#13744](https://github.com/anthropics/claude-code/issues/13744), [#26923](https://github.com/anthropics/claude-code/issues/26923)
- Copilot CLI custom slash commands not supported: [issue #1113](https://github.com/github/copilot-cli/issues/1113)
- Karpathy on iterative loops (Autoresearch pattern): measure → change → check → keep/revert. Underlies the auto-apply reflect rollback design.

---

## Suggested narrative arcs (pick one)

1. **"Building an agentic coding kit that works across Claude Code, OpenCode, and Copilot CLI"** — cross-host architecture story; per-host frontmatter sanitization as the technical surprise; BOM bug as the dramatic mid-section reveal.
2. **"Why my orchestrator subagents were the wrong abstraction"** — the Tier-D → Tier-E pivot; cite ECC + barkain. Honest mid-build course-correction story. Most relatable arc for engineers who've built agent kits.
3. **"More critics is not more rigor"** — focused on PR #5's adversarial demote + spawn-budget v2 + auto-apply reflect. Counterintuitive — multi-agent kits often add agents to add rigor; this is a story about deleting agents to add rigor.
4. **"What real PR reviewers actually check, baked into a sub-agent"** — focused on `pr-reviewer`. Shorter, narrower; pairs with the Google/Conventional-Comments lineage.
5. **"The 84 duplicate skills and the BOM bug — silent failure modes in agent kits"** — debugging-story angle. Less architectural, more "field notes."

All five are real arcs from this sprint. Arcs 2 and 3 are the strongest "this taught me something I didn't know going in" stories — likely best fits for Medium.
