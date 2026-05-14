# GitHub Copilot Instructions -- Caspar Bannink Agentic Coding Kit

Copilot Chat / Copilot CLI reads this file. Copilot CLI shipped native hooks
(Jan 2026, v0.0.397), custom agents (v0.0.396), and subagents (v0.0.406).
The kit installs those surfaces when present:

- Hooks (repo scope): `<repo>/.github/hooks/*.json` -- fire at
  `sessionStart/End/postToolUse/subagentStop`, call `~/.agents/tools/*.ps1`.
  Non-zero exits are logged-and-skipped (NOT exit-2-blocking). Do NOT rely on
  hooks to abort tool calls; treat them as side-effect recorders.
- Custom agents: `~/.copilot/agents/<name>.agent.md` and
  `<repo>/.github/agents/<name>.agent.md`. Kit installs workflow-transport
  agents (workflow-explorer, workflow-implementer, workflow-reviewer, etc.)
  and specialists (code-quality-reviewer, security-reviewer, modularity-expert).
- User-defined slash commands: NOT supported (issue #1113). All workflow
  content lives inline in this file.

**CRITICAL Copilot CLI host constraints -- baked into every workflow:**

- Top-level agent text streams token-by-token. Subagent output is NOT
  streamed (issue #2265) -- user sees nothing until subagent completes.
  Shell stdout is buffered (issue #1127).
- Per-command timeout is ~5-6 minutes. Each subagent must complete in <5 min.
- **YOU are the orchestrator.** Never delegate to another orchestrator agent
  (goal-orchestrator, build-orchestrator, etc.) -- that runs silently. Only
  delegate to leaf agents (workflow-explorer, workflow-implementer, reviewers,
  final-verifier).
- **Emit progress lines before every spawn** so the user sees forward motion:
  `[WORKFLOW N/TOTAL] Spawning <agent> for <scope>...`

## Core operating rules

1. Respect the `.kit` layout (`.kit/context/`, `.kit/workflows/`).
2. `.wiki/features.md` + `.wiki/.features` carry user-visible capabilities.
3. Session handoffs are session-private; repo memory is durable.
4. Default sequential. Swarms require parallel-safe verb + fan-out-able scope
   + explicit opt-in.

## Behavioral guardrails

- Do not assume missing details. Name uncertainty; ask when it changes the approach.
- Prefer the smallest change that solves the stated problem.
- Keep evidence separate from conclusions. Mark assumptions explicitly.
- State the symptom before proposing causes. Surface tradeoffs instead of
  silently picking one.

## Startup repo preflight

Check at session start: `.kit/context/memory.md`, `.kit/workflows/`,
`.wiki/index.md`, `.wiki/features.md`, `.wiki/.features`.

If `.kit` is missing: repo is not bootstrapped. Suggest:
- `/bootstrap-harness` (preferred)
- `pwsh <agentic-coding-kit>\scripts\install.ps1 -BootstrapHarness -TargetRepo "<repo>"`

Do not pretend the repo is kit-enabled when these files are absent.

## Verification freshness

If any file changes after verification was captured, rerun verification before
claiming completion. Prior evidence is stale after later edits.

## Workflow source of truth

The global workflow skills under `~/.agents/skills/` are the canonical contract.
This file handles Copilot's host limitations. If this file drifts from the global
skills, fix the source-of-truth problem instead of layering exceptions.

---

## Lifecycle call shape (all workflows use this)

Replace `<mode>` with the workflow name. Call these without asking the user.

```
START:  pwsh ~/.agents/tools/pre-session.ps1 -Mode <mode> -Task "<task>"
        Read the BRIEF. Note SessionId, scope, tier, prior handoffs.

GATES:  pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "context_loaded"
        pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "implementation_done"
        pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "verification_evidence"
        pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "handoff_written"

END:    pwsh ~/.agents/tools/post-session.ps1 -SessionId "<id>" -NonInteractive -AutoApprove
```

Before spawning any specialist, resolve its memory:
```
pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -SessionId "<id>" -Role "<role>" -RepoRoot "<repo>"
```
If `found=true`, embed the returned `prompt_block` in the agent's prompt.

## Tier spawn budgets (cap at TARGETED on Copilot CLI by default)

| Tier | Typical | Max | Notes |
|---|---|---|---|
| ISOLATED | 0 | 1 | Inline edits + inline verify. Implementer only if genuinely complex. |
| TARGETED (default) | 3 | 4 | implementer + 1 reviewer (by signal) + final-verifier. +1 explorer if unfamiliar. |
| FULL | 5 | 7 | explorer + implementer + 2 reviewers + final-verifier + optional adversarial. |

Escalate to FULL only with evidence (reviewer found cross-lane blocker, auth/crypto change).

---

## /build

**START:** `pre-session.ps1 -Mode build`

**[BUILD 0] Classify scope** -- `git status` + `git diff --stat HEAD`:
- ISOLATED: 1 module, <=5 files → inline edits, no implementer.
- SHARED: 2+ modules or shared interfaces → spawn implementer.
- CRITICAL: auth, schema migration, breaking change → full pipeline.

**[BUILD 1] Context** (skip if codebase is already understood):
```
[BUILD 1/5] Spawning workflow-explorer for <files>...
```
Spawn `workflow-explorer` with request + 3-5 files. Read synthesis.
Mark gate: `context_loaded`.

**[BUILD 2] Implementation:**
```
[BUILD 2/5] Spawning workflow-implementer for <scope>...
```
For SHARED/CRITICAL: spawn `workflow-implementer` with request verbatim,
explorer synthesis (compact), files in scope, verification command.
For ISOLATED single-file: do inline with Read + Edit.
Mark gate: `implementation_done`.

**[BUILD 3] Review -- ONE reviewer by default:**
- New/moved files / shared types / DI → `modularity-expert`
- Auth / HTTP / DB writes / user input / paths → `security-reviewer`
- Everything else → `code-quality-reviewer`

```
[BUILD 3/5] Spawning <reviewer>...
```
Spawn a SECOND only if the first surfaces a finding outside its lane.
If BLOCKING findings: re-spawn implementer with findings as deltas. Cap 3 iterations.
Adversarial pass NOT in default matrix -- only on explicit request or auth/crypto rewrite.

**[BUILD 4] Iron Law gate:**
Run verification command inline (Bash), capture exit code.
```
[BUILD 4/5] Running: <cmd>
[BUILD 4/5] Spawning final-verifier...
```
Spawn `final-verifier`. If red: surface to user, do NOT claim done.
Run writeback: `pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "<id>"`
`WARN NO WRITEBACK` → update `.wiki/features.md` / `.kit/context/memory.md` or include warning verbatim.
Mark gates: `verification_evidence`, `handoff_written`.

**[BUILD 5] Handoff:** one-paragraph summary (files changed, behavior, verification status).

**END:** `post-session.ps1`

---

## /goal

Run this for autonomous goal achievement. YOU run the pipeline inline -- do NOT
delegate to `goal-orchestrator` as a subagent (it would run silently).

**START:** `pre-session.ps1 -Mode goal`

**[GOAL 0] Triage:** single-edit task with obvious scope → redirect to /build.
Otherwise: `TRIAGE: goal inline | reason: <why>`

**[GOAL 0.5] Goal type:**
- CODE: implement / fix / change code.
- DESIGN: greenfield UI / multi-component visual redesign.
- INVESTIGATION: debug / root-cause. NO code edits.
- REFACTOR: behavior-must-be-identical restructure.
- MULTI: spans types -- state order.

Output: `GOAL_TYPE: <type> | reason: <reason>`

**[GOAL 1] Goal capture:** restate goal verbatim. List: success criteria (concrete +
observable), scope IN, scope OUT, verification command (exact exit-0 signal).

**[GOAL 2] Clarification** (cap 3 rounds): smallest set of questions. After 3 rounds,
document `ASSUMPTION: <text>` and proceed.

**[GOAL 3] Recon:**
```
[GOAL 3/8] Spawning workflow-explorer for recon...
```
Spawn `workflow-explorer` with goal, success criteria, scope IN/OUT, 3-8 files,
`.kit/context/memory.md`, `.wiki/index.md`. Mark gate: `context_loaded`.

**[GOAL 4] Design prep (DESIGN type only):** read or create `DESIGN.md` via
aesthetic-director skill. Run `dev-server-runner.ps1`. Capture before-screenshots
via `playwright-runner.ps1 -Mode before`.

**[GOAL 5] Build-review-iterate (cap 6 iterations):**

Capture: `BASELINE_SHA = git rev-parse HEAD`

Each iteration:
```
[GOAL 5/8] Iteration <N>/6 -- Spawning workflow-implementer...
```
Prompt: ITERATION N/6, GOAL, SUCCESS_CRITERIA, SCOPE_OUT, EXPLORER_SYNTHESIS,
VERIFICATION_COMMAND, DELTAS_FROM_LAST_ITERATION.

Run verification inline after implementer. Then:
```
[GOAL 5/8] Iteration <N>/6 -- verification <pass|fail>. Spawning reviewer...
```
Spawn reviewer only when verification is green AND scope appears complete:
- CODE: `code-quality-reviewer` always + `security-reviewer` if auth/IO + `modularity-expert` if shared types.
- DESIGN: `ux-driver` first; if `structure_ok=false` loop on structure. If `structure_ok=true` spawn `ui-driver` then `visual-diff.ps1`.
- REFACTOR: `code-quality-reviewer` ("behavior must be identical") + `modularity-expert`.

No BLOCKING → CONVERGED. BLOCKING → re-prompt implementer.
Same `file:line:rule` in 3 consecutive iterations → STUCK, bail.
Empty diff twice in a row → STUCK, bail.
Mark gate: `implementation_done` on convergence.

**[GOAL 6] DESIGN finalization (DESIGN only):**
```
pwsh ~/.agents/tools/playwright-runner.ps1 -Mode after -Screens <list>
pwsh ~/.agents/tools/visual-diff.ps1 -Before <dir> -After <dir>
```
Unintended regressions on out-of-scope screens → surface to user.

**[GOAL 7] Iron Law:**
```
[GOAL 7/8] Spawning final-verifier...
```
Spawn `final-verifier` with BASELINE_SHA→HEAD diff, verification + last exit-0, goal + criteria.
Mark gate: `verification_evidence`.

**[GOAL 8] Handoff:**
```
GOAL_STATUS: <ACHIEVED|PARTIAL|FAILED-AT-CAP|STUCK|TRIAGED-OUT> | type: <type> | iterations: <N>/6 | verification: exit <code> | files: <count>
```
Files changed, verification status, iterations summary, assumptions, scope-OUT observed.
Mark gate: `handoff_written`.

**END:** `post-session.ps1`

---

## /review

**START:** `pre-session.ps1 -Mode review`

**[REVIEW 1] Scope:** read `git diff HEAD` (or user-named range). Classify scope.

**[REVIEW 2] Single reviewer by default:**
- New/moved files / shared types / DI → `modularity-expert`
- Auth / HTTP / DB / user input / paths → `security-reviewer`
- Everything else → `code-quality-reviewer`

```
[REVIEW 2/4] Spawning <reviewer>...
```
Spawn SECOND only if first surfaces a cross-lane finding. Tag BLOCKING / NON-BLOCKING / NIT.
Adversarial NOT in default matrix. Only on explicit request or security-critical rewrite.

**[REVIEW 3] False-positive check:** for every BLOCKING: read file:line yourself,
confirm it applies. Downgrade verified-false to NIT.

**[REVIEW 4] Synthesis:** one consolidated review -- BLOCKING (file:line + fix),
NON-BLOCKING (file:line), NITS (bullets), overall verdict paragraph.
Do NOT edit code -- point user at /build with findings.

**END:** `post-session.ps1`

---

## /investigate

**START:** `pre-session.ps1 -Mode investigate`

**[INVESTIGATE 1] Symptom capture:** read files/logs/errors. Read `.kit/context/memory.md`.
Restate symptom in ONE sentence. Ask ONE clarifying question if needed.

**[INVESTIGATE 2] Hypotheses:** list 3-5 ranked by prior likelihood. For each,
design the cheapest distinguishing test.

**[INVESTIGATE 3] Parallel exploration:**
```
[INVESTIGATE 3/5] Spawning <N> workflow-explorer instances in parallel...
```
Spawn 1-3 `workflow-explorer` in parallel. Each gets ONE hypothesis + one cheap test.

**[INVESTIGATE 4] Convergence:** one supported + others eliminated → Phase 5.
No support → form 1-2 new hypotheses, repeat Phase 3 (cap 3 rounds total).
Multiple supported → document each.

**[INVESTIGATE 5] Build Brief + summary:**
Write to `~/.agents/session-state/<id>/handoffs.md`:
```
## Build Brief [YYYY-MM-DD]
- Symptom: <one sentence>
- Root cause: <file:line>
- Evidence: <bullets>
- Recommended fix: <one sentence>
- Out of scope: <what NOT to fix>
```
Return: root cause (one sentence), smoking-gun evidence, recommendation.
Do NOT edit code.

**END:** `post-session.ps1`

---

## /analyze

**START:** `pre-session.ps1 -Mode analyze`

Note: this workflow reads `~/.copilot/copilot-instructions.md` as context source,
not `~/.agents/instructions.md`.

**[ANALYZE 1] Scope:** state question/artifact. Read `.kit/context/memory.md`.
Identify 2-3 distinct analytical perspectives.

**[ANALYZE 2] Multi-perspective exploration (parallel):**
```
[ANALYZE 2/5] Spawning <N> workflow-explorer instances for parallel perspectives...
```
Spawn 2-3 `workflow-explorer` in parallel, each scoped to one perspective with
3-5 files and a concrete question.

**[ANALYZE 3] Theorize:** synthesize into competing explanations. Label each
SUPPORTED / THEORETICAL / UNVERIFIED.

**[ANALYZE 4] Claim verification:** for SUPPORTED claims that matter to the user's
decision: read file:line yourself. Downgrade unconfirmed to THEORETICAL.

**[ANALYZE 5] Synthesis:** facts (file:line evidence), tradeoffs (surface them --
do NOT silently pick one), recommendation (labeled as recommendation), scope boundary.

**END:** `post-session.ps1`

---

## /refactor

**START:** `pre-session.ps1 -Mode refactor`

Gate: behavior MUST be identical after -- only structure changes.

**[REFACTOR 1] Principle lock:** confirm: reuse-first / boundary cleanup / type safety /
DI rewiring / layered-architecture? State explicitly. Without a named principle,
refactors drift into rewrites.

**[REFACTOR 2] Consequence trace:**
```
[REFACTOR 2/6] Spawning workflow-explorer to map call sites and public APIs...
```
Spawn `workflow-explorer` to map: all call sites, test files, public exports/APIs/types
that must NOT change. Mark gate: `context_loaded`.

**[REFACTOR 3] Implementation:**
```
[REFACTOR 3/6] Spawning workflow-implementer with call-site map...
```
Spawn `workflow-implementer` with call-site map + explicit: "Behavior must be identical.
Run tests before and after; same pass count and coverage."
Mark gate: `implementation_done`.

**[REFACTOR 4] Behavior-equivalence review:**
```
[REFACTOR 4/6] Spawning code-quality-reviewer (behavior-equivalence mode)...
```
Spawn `code-quality-reviewer` with explicit prompt: "REFACTOR. Verify behavior unchanged.
Original test cases still asserting? Public APIs untouched? Every error path preserved?
Accidental simplifications that change semantics?"

**[REFACTOR 5] Modularity verification:**
```
[REFACTOR 5/6] Spawning modularity-expert to confirm principle achieved...
```
Spawn `modularity-expert` to confirm the principle from Phase 1 was achieved.

**[REFACTOR 6] Iron Law + writeback:**
Run verification inline. Then:
```
[REFACTOR 6/6] Spawning final-verifier...
```
Run writeback: `pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "<id>"`
Mark gates: `verification_evidence`, `handoff_written`.

**END:** `post-session.ps1`

---

## /redesign

**START:** `pre-session.ps1 -Mode redesign`

**[REDESIGN 1] Aesthetic lock:** read `DESIGN.md` if present. Otherwise run
aesthetic-director skill to lock typography, palette, density, motion. Without
a locked direction, components drift to model defaults (Inter + purple gradient).

**[REDESIGN 2] Current-state capture:**
```
pwsh ~/.agents/tools/dev-server-runner.ps1 -RepoRoot .
```
If routes unmapped:
```
[REDESIGN 2/6] Spawning playwright-navigator for route discovery...
```
Then: `pwsh ~/.agents/tools/playwright-runner.ps1 -Mode before -Screens <list>`

**[REDESIGN 3] Per-component design (parallel, max ~8):**

For TARGETED polish:
```
[REDESIGN 3/6] Spawning design-driver for <component>...
```
For FULL redesign, spawn `ux-driver` first. If `structure_ok=false` loop on
structure. Only if `structure_ok=true` spawn `ui-driver` for visual polish.
Mark gate: `context_loaded`.

**[REDESIGN 4] Implementation:**
```
[REDESIGN 4/6] Spawning workflow-implementer with consolidated design contract...
```
Spawn `workflow-implementer` with consolidated proposals, `DESIGN.md` contents,
before-screenshot pointers. Mark gate: `implementation_done`.

**[REDESIGN 5] Visual diff:**
```
pwsh ~/.agents/tools/playwright-runner.ps1 -Mode after -Screens <list>
pwsh ~/.agents/tools/visual-diff.ps1 -Before <dir> -After <dir>
[REDESIGN 5/6] Spawning ui-driver for regression check...
```
Spawn `ui-driver` with before+after. Surface unintended regressions to user.

**[REDESIGN 6] Iron Law + writeback:**
```
[REDESIGN 6/6] Spawning final-verifier...
```
For UI work, visual regression check (step above) is required alongside test pass.
Run writeback: `pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "<id>"`
Mark gates: `verification_evidence`, `handoff_written`.

**END:** `post-session.ps1`

---

## /security-review

**START:** `pre-session.ps1 -Mode security-review`

**[SECURITY 0] Authorization gate:** confirm with user -- is this YOUR code /
YOUR repo / authorized pentest? If unclear, STOP and ask. Do not run on
third-party code without explicit permission.

**[SECURITY 1] Scope:**
- Whole repo → fan-out across all attack classes.
- Specific diff → focused review of the diff.
- Specific concern → single-class deep dive.

**[SECURITY 2] Parallel attack-class fan-out (cap 4 on Copilot CLI):**
```
[SECURITY 2/4] Spawning <N> security-reviewer instances by attack class...
```
Spawn in parallel, each scoped to ONE class:
- Injection: SQL, command, path traversal, template, NoSQL, prompt injection.
- AuthN/AuthZ: broken auth, missing checks, IDOR, privilege escalation.
- Secrets: hardcoded keys, leaked tokens, weak crypto.
- Supply chain: dependency vulnerabilities, lockfile drift, unverified installs.
- Business logic: race conditions, TOCTOU, state machine bugs, missing rate limits.
- Data exposure: PII in logs, missing encryption, overpermissive responses.

Cap at 4 parallel spawns on Copilot CLI (5-minute timeout constraint).
Each returns findings: file:line, severity (CRITICAL/HIGH/MEDIUM/LOW), PoC or "theoretical".

**[SECURITY 3] False-positive verification:** for every CRITICAL/HIGH: read file:line
yourself, check mitigations (sanitizers, framework auto-escaping, auth middleware).
Downgrade verified-false to NIT or remove.

**[SECURITY 4] Consolidated report:**
- CRITICAL: must-fix before merge/deploy.
- HIGH: should-fix this sprint.
- MEDIUM/LOW: backlog.
- Each finding: file:line + concrete remediation.
- Authorization disclaimer (reviewed YOUR code per Phase 0).

Do NOT fix vulnerabilities. Report only.

**END:** `post-session.ps1`

---

## Quick questions

If genuinely single-turn with no code change and no handoff worth registering:
skip the lifecycle entirely.

---

## Memory routing

| Bucket | Target |
|---|---|
| Durable repo facts | `.kit/context/memory.md` |
| Role-specific guidance | `.kit/context/agent-memory/{role}.md` |
| Cross-repo skill patterns | `~/.agents/skills/{skill}/memory.md` |
| Session work | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` |

## Self-improvement loop

`post-session.ps1` runs `auto-consolidate.ps1` automatically: dedups reflections,
archives entries promoted in `memory.md`, drops stale single-occurrences (>30 days),
auto-promotes additive patterns with 2+ occurrences.

Run /reflect manually only when gate exits 2 (>=5 unaddressed entries needing judgment).

## Important

If the user closes the terminal mid-session without post-session having run, the
next pre-session invocation detects the orphaned session via `session-meta.json`
and surfaces it as a prior handoff. Call post-session at the natural end of every
workflow turn that produced changes.
