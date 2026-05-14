# GitHub Copilot Instructions -- Caspar Bannink Agentic Coding Kit

Copilot Chat / Copilot CLI reads this file. Copilot CLI shipped native
session/tool hooks (Jan 2026, v0.0.397) and custom agents (Jan 2026,
v0.0.396) plus subagents (Feb 2026, v0.0.406). The kit installs those
surfaces when present:

- Hooks (repo scope only, per docs): `<repo>/.github/hooks/*.json` --
  installed by `pwsh ./install.ps1 -TargetRepo <r> -InstallAdapter copilot`.
  These fire deterministically (`sessionStart`, `sessionEnd`, `postToolUse`,
  `subagentStop`) and call the kit's PowerShell lifecycle scripts at
  `~/.agents/tools/`. Non-zero exits are logged-and-skipped on Copilot
  (NOT exit-2-blocking like Claude Code), so do NOT rely on hooks to
  abort tool calls; treat them as side-effect recorders.
- Custom agents (user + repo scope): `~/.copilot/agents/<name>.agent.md`
  and `<repo>/.github/agents/<name>.agent.md`. The kit installs both
  workflow-transport agents (workflow-explorer, workflow-implementer,
  workflow-reviewer, workflow-skeptic, workflow-ui-qa) and specialist
  agents (code-quality-reviewer, security-reviewer, modularity-expert,
  etc.) via the device-wide and per-repo install paths.
- User-defined slash commands: NOT supported by Copilot CLI (issue #1113).
  The kit's procedural workflow content lives inline in this file and in
  `~/.copilot/agentic-kit.md`.

## Copilot CLI entrypoints

Copilot CLI still does **not** support user-defined slash commands, so the kit
uses the two supported entrypoint styles below instead:

- **Shell wrappers** installed by `pwsh ./scripts/install.ps1 -For copilot` at
  `~/.agents/bin/copilot/`:
  `kit-analyze.sh`, `kit-bootstrap.sh`, `kit-build.sh`, `kit-goal.sh`, `kit-investigate.sh`, `kit-plan.sh`,
  `kit-pr-review.sh`, `kit-refactor.sh`, `kit-redesign.sh`, `kit-review.sh`,
  `kit-security-review.sh`.
  Per-repo installs also plant repo-local copies at `.github/copilot-bin/`; direct Copilot agents should prefer those repo-local paths when present.
  Matching PowerShell shims are also installed (`kit-build.ps1`, etc.) for Windows hosts where `bash` is not on `PATH`.
  Invoke with `pwsh .github\copilot-bin\kit-build.ps1 "<request>"` inside a bootstrapped repo on Windows, or fall back to `pwsh ~/.agents/bin/copilot/kit-build.ps1 "<request>"`.
  For PR review: `pwsh ~/.agents/bin/copilot/kit-pr-review.ps1 "<PR number or context>"` on Windows.
  For repo bootstrap (AI phases after scaffold): `pwsh ~/.agents/bin/copilot/kit-bootstrap.ps1 "<repo-root>"` on Windows.
- **Direct custom-agent calls** when one installed agent is the cleanest fit:
  - `copilot --agent goal-orchestrator -p "Achieve this autonomously: <goal>"`
  - `copilot --agent pr-reviewer -p "Review the current PR in this repo."`
  - `copilot --agent security-reviewer -p "Security audit of: <scope>"`
  - `copilot --agent ux-driver -p "UX critique for: <scope>"`

When a task maps cleanly to one direct agent, prefer that over inventing an
unsupported `/build`-style command.

When you (the agent) cannot find a hook firing, fall back to calling the
harness scripts directly from the workflow body -- the lifecycle calls
below remain valid even when hooks are missing.

## Core operating rules

1. Respect the `.kit` layout (`.kit/context/`, `.kit/workflows/`).
2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.
3. Session handoffs are session-private; repo memory is durable.
4. Default sequential. Swarms require parallel-safe verb + fan-out-able
   scope + explicit opt-in.

## Behavioral guardrails

- Do not assume missing details. Name uncertainty and ask when it changes the approach.
- Prefer the smallest change that solves the stated problem. Avoid speculative flexibility.
- Keep evidence separate from conclusions. Mark assumptions and unverified claims explicitly.
- For debugging, state the symptom before proposing causes. For analysis, surface tradeoffs instead of silently picking one.

## Startup repo preflight

At session start, detect whether the current repo has the kit scaffold. Check:

- `.kit/context/memory.md`
- `.kit/workflows/`
- `.wiki/index.md`
- `.wiki/features.md`
- `.wiki/.features`

**If `.kit` is missing OR `.wiki/index.md` is missing:**
Do NOT suggest bootstrap to the user and wait. **Execute the bootstrap-harness
workflow yourself immediately:**

1. Read `~/.agents/skills/bootstrap-harness/SKILL.md` completely.
2. Execute every phase inline (Phase 0 → Phase 6):
   - Phase 1: git-archaeology + convention detection → write `.kit/context/conventions.md`
   - Phase 2: scaffold (call `pwsh <kit>/scripts/install.ps1 -BootstrapHarness -TargetRepo <repo>`)
   - Phase 3: kit-init → write `.kit/context/memory.md` and sibling files
   - Phase 4: wiki-init → write `.wiki/{index,architecture,codebase,features}.md`
   - Phase 5: convergence check; retry up to 3 iterations if any required file is missing/empty
   - Phase 6: emit machine-parseable `BOOTSTRAP_STATUS:` handoff line
3. Only after bootstrap completes, proceed with the user's actual task.

Alternative for command-line invocation: `pwsh ~/.agents/bin/copilot/kit-bootstrap.ps1 <repo>` on Windows or `bash ~/.agents/bin/copilot/kit-bootstrap.sh <repo>` on POSIX
chains the same phases through Copilot agents automatically — it will also run
the scaffold step itself if the repo is not yet planted.

**If only `.kit/context/conventions.md` is a placeholder** (under 400 bytes or
contains `_not yet detected_`): execute Phase 1 of bootstrap-harness inline
(git-archaeology + workflow-convention detection) to produce real content. This
ensures downstream agents follow YOUR repo's actual patterns rather than generic
defaults. Skip the full scaffold for this case.

Do not pretend the repo is fully kit-enabled when files are absent. For
genuinely single-turn questions (no code change, no `.git`) the preflight can
be skipped, but warn that convention-aware behavior is degraded.

## Goal-orchestrator

`goal-orchestrator` is a first-class custom agent. Invoke it directly:

```
copilot --agent goal-orchestrator -p "Achieve this autonomously: <goal>"
```

Or via the shell wrapper: `pwsh ~/.agents/bin/copilot/kit-goal.ps1 "<goal>"` on Windows or `bash ~/.agents/bin/copilot/kit-goal.sh "<goal>"` on POSIX

It classifies the goal type (CODE / DESIGN / INVESTIGATION / REFACTOR / BOOTSTRAP /
MULTI) and runs the matching pipeline end-to-end with iteration and review gates.
When it detects BOOTSTRAP type (missing `.kit/` or `.wiki/`) it reads and
executes the bootstrap-harness skill automatically — producing the same result
as Claude Code's `/bootstrap-harness` command.

Note: Copilot CLI does not support user-defined slash commands (issue #1113).
`/goal-orchestrator` as a slash command does not exist. Use the direct agent
call above, the kit-goal.sh wrapper, or say "use goal-orchestrator to achieve
<goal>" and this agent will delegate appropriately.

## Verification freshness

If any file changes after verification was captured, rerun verification before claiming completion. Treat prior evidence as stale after later edits.

## Workflow source of truth

The **global workflow skills** under `~/.agents/skills/` are the canonical
workflow contract. This file exists to handle Copilot's host limitations
(especially no user-defined slash commands, repo-scoped hooks only, and no
documented skills auto-discovery), not to redefine how `/build`, `/review`, or
the other workflows are supposed to behave.

If this file drifts from the global workflow skills, fix the source-of-truth
problem instead of layering more Copilot-specific exceptions.

## Lifecycle baked into every command

Even with hooks installed, every workflow command should explicitly call
the lifecycle scripts. **Do this without asking the user; it's the contract.**

### When the user says /build (or asks to implement, fix, refactor):

```
1. RUN: pwsh ~/.agents/tools/pre-session.ps1 -Mode build -Task "<task>"
       Read the BRIEF block it emits. Note the SessionId, scope, tier,
       swarm mode, prior handoffs.

2. IF tierRec is INLINE: do the work in this turn, no sub-agents.
   IF TARGETED: spawn 1-3 reviewers via the workflow.
   IF FULL or SWARM: follow the full agent matrix from
   ~/.agents/skills/build/SKILL.md.

3. Implement only the scoped change. Mark gates as you complete them:
       pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "context_loaded"
       pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "implementation_done"
       (etc.)

4. Capture verification evidence (test output, build output) before claiming
   completion. Mark verification_evidence.

5. RUN: pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove
       This auto-consolidates reflections and gates on accumulated backlog.
```

The build semantics themselves still come from `~/.agents/skills/build/SKILL.md`.
Copilot's custom-agent surface (.agent.md files) is now wired by the kit; subagents are spawnable. The workflow contract is the
same: respect the same phases, gates, memory routing, and read-stop discipline
instead of inventing a smaller Copilot-only build.

### When the user says /review, /plan, /analyze, /investigate, /refactor:

Same shape. Replace `-Mode build` with the matching mode. The lifecycle
calls are NOT optional -- they're how the kit's memory and self-improvement
loop survive across Copilot sessions.

### When the user says /redesign (or asks to redesign UI, restyle, redesign a component):

```
1. RUN: pwsh ~/.agents/tools/pre-session.ps1 -Mode build -Task "redesign: <task>"
       Note SessionId.

2. Run the redesign pipeline via the shell wrapper:
       bash ~/.agents/bin/copilot/kit-redesign.sh "<what to redesign>"

   This chains:
     - ux-driver  → UX critique (information architecture, scannability, a11y)
     - ui-driver  → UI visual critique (typography, color, spacing, density, motion)
     - workflow-implementer → applies changes from both critiques
   Session artifacts at .kit/session-state/<ts>-redesign/ by default (or `${AGENTS_SESSION_ROOT}` if overridden)

3. RUN: pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove
```

Direct agent invocation (critique-only, no implementation):
```
copilot --agent ux-driver -p "UX critique for: <scope>"
copilot --agent ui-driver -p "UI visual critique for: <scope>"
```

### When the user says /security-review (or asks for a security audit, adversarial security review, pen test of the code):

Authorization gate: this workflow is for YOUR code / YOUR repo / authorized engagement only.

```
1. RUN: pwsh ~/.agents/tools/pre-session.ps1 -Mode review -Task "security-review: <scope>"
       Note SessionId.

2. Run the security fan-out via the shell wrapper:
       bash ~/.agents/bin/copilot/kit-security-review.sh "<scope>"

   This fans out FOUR parallel attack-class reviewers:
     - injection (SQL, command, path traversal, template, prompt injection)
     - auth (broken auth, missing checks, IDOR, privilege escalation)
     - secrets (hardcoded keys, leaked tokens, weak crypto)
     - biz-logic (race conditions, TOCTOU, state machine bugs, rate limits)
   Then synthesizes a consolidated CRITICAL/HIGH/MEDIUM/LOW report with
   file:line citations and concrete remediation steps.
    Session artifacts at .kit/session-state/<ts>-secrev/ by default (or `${AGENTS_SESSION_ROOT}` if overridden)

3. RUN: pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove
```

Direct agent invocation (single attack class):
```
copilot --agent security-reviewer -p "Injection review for: <scope>"
```

### When the user says /pr-review (or "review my PR", "review this PR", "review the diff before I merge"):

This is DISTINCT from /review (diff-only code review). The pr-reviewer reads the full PR
holistically: title, description, commits, diff, CI status, repo conventions → APPROVE /
REQUEST_CHANGES / COMMENT verdict with blocking/non-blocking/nit breakdown.

```
1. RUN: pwsh ~/.agents/tools/pre-session.ps1 -Mode review -Task "pr-review: <PR context>"
       Note SessionId.

2. Run the PR reviewer via the shell wrapper:
       bash ~/.agents/bin/copilot/kit-pr-review.sh "<PR number or context>"

   OR invoke the agent directly (it handles all phases itself):
       copilot --agent pr-reviewer -p "Review the current PR in this repo."

   The pr-reviewer agent:
   - Auto-runs bootstrap-harness if .kit/context/conventions.md is missing/placeholder
   - Reads .wiki/ docs for architecture + feature context
   - Samples prior PR review style from git/gh history to calibrate tone/threshold
   - Phase 0→4: repo context → holistic read → scope check → dimension checklist → synthesis
   - Outputs verdict line: PR_REVIEW: <APPROVE|REQUEST_CHANGES|COMMENT>
    Session artifacts at .kit/session-state/<ts>-pr-review/ by default (or `${AGENTS_SESSION_ROOT}` if overridden)

3. RUN: pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove
```

For CI/CD pipeline integration, the pr-reviewer agent's first output line is
machine-parseable (`PR_REVIEW: APPROVE | ...`) and can gate merges in automated pipelines.

### When the user says /goal (or "achieve this autonomously", "drive this to completion"):

```
1. RUN: pwsh ~/.agents/tools/pre-session.ps1 -Mode goal -Task "<goal>"
       Read the BRIEF block. Note SessionId and any prior handoffs.

2. Classify goal type: CODE / DESIGN / INVESTIGATION / REFACTOR / SECURITY / PR_REVIEW / BOOTSTRAP / MULTI.

3. Route to the matching workflow:
   - CODE / REFACTOR  → bash ~/.agents/bin/copilot/kit-build.sh "<goal>"
   - INVESTIGATION    → bash ~/.agents/bin/copilot/kit-investigate.sh "<symptom>"
   - ANALYSIS         → bash ~/.agents/bin/copilot/kit-analyze.sh "<question>"
   - REVIEW-only      → bash ~/.agents/bin/copilot/kit-review.sh "<diff context>"
   - PR_REVIEW        → bash ~/.agents/bin/copilot/kit-pr-review.sh "<PR number or context>"
   - DESIGN / REDESIGN→ bash ~/.agents/bin/copilot/kit-redesign.sh "<what to redesign>"
   - SECURITY         → bash ~/.agents/bin/copilot/kit-security-review.sh "<scope>"
   - BOOTSTRAP        → bash ~/.agents/bin/copilot/kit-bootstrap.sh "$(pwd)"
   - MULTI            → run each matching wrapper in sequence

4. Iterate (cap: 6) until verification passes or stuck detection fires.

5. RUN: pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove
```

Direct agent invocation (alternative to the wrapper):
```
copilot --agent goal-orchestrator -p "Achieve this autonomously: <goal>"
```
or via shell wrapper:
```
bash ~/.agents/bin/copilot/kit-goal.sh "<goal>"
```

### When the user just asks a quick question:

If the request is genuinely a single-turn answer (no code change), skip the
lifecycle. Lifecycle is for sessions that produce a handoff worth registering.

## Memory routing

| Bucket | Target |
|---|---|
| Durable repo facts | `.kit/context/memory.md` |
| Role-specific guidance | `.kit/context/agent-memory/{role}.md` |
| Cross-repo skill patterns | `~/.agents/skills/{skill}/memory.md` |
| Session work | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` (default `.kit/session-state/{id}/handoffs.md` in a bootstrapped repo, else `~/.agents/session-state/{id}/handoffs.md`) |

Copilot's own host-native runtime state under `~/.copilot/session-state/` is
not changed by these repo instructions; only kit-managed artifacts move.

Before spawning a specialist role, run:

```
pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId "<id>" -Role "<role>" -RepoRoot "<repo>"
```

If `found=true`, embed the returned `prompt_block` in the spawned role's
prompt. Do not skip this step -- it's how role memory works.

## Self-improvement loop

`post-session.ps1` runs `auto-consolidate.ps1` automatically. It:
- dedups identical reflection entries
- archives entries already promoted in `memory.md`
- drops stale single-occurrence entries (>30 days)
- auto-promotes additive patterns with 2+ occurrences

You usually don't need to run /reflect manually. Only when the gate exits 2
(>=5 unaddressed entries that need judgment) should you read the entries
and run the /reflect workflow.

## Important

If the user closes the terminal mid-session without you having called
post-session, the next pre-session invocation will detect the orphaned
session via session-meta.json and surface it as a prior handoff. Don't
panic; the kit is resilient. But the BEST behavior is to call post-session
at the natural end of every workflow turn that produced changes.
