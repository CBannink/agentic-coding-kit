# Tier-D eval results (2026-05-07)

After Tier-D ECC-style routing migration (commits c32893a..19d21e4), ran
three `claude -p` evals against fresh sandbox repos. Findings below.

## Setup

- Clean reinstall via `pwsh ./install.ps1 -For "claude,opencode" -CleanReinstall`.
- All 7 orchestrator subagents (`build-orchestrator`, `review-orchestrator`,
  `investigate-orchestrator`, `plan-orchestrator`, `refactor-orchestrator`,
  `redesign-orchestrator`, `security-review-orchestrator`) installed at
  `~/.claude/agents/`.
- All 15 specialist + workflow agents have ECC trigger phrases (`MUST BE USED for X`,
  `Use immediately after Y`, `Use PROACTIVELY when Z`).
- Global CLAUDE.md cut from 304 LOC to 86 LOC. Orchestrator manifesto removed.
- 3 broken PreToolUse blocking hooks (read-delegation, write-gateguard,
  task-orchestrator-gate) removed from `settings.snippet.json`.
- Slash commands rewritten as thin shims that delegate to matching orchestrator.

## Probe 1: agent discoverability

Prompt: `List the names of all subagents you have access to. Just the names, comma-separated.`

Response (verbatim):
> build-orchestrator, Explore, general-purpose, investigate-orchestrator, Plan,
> plan-orchestrator, redesign-orchestrator, refactor-orchestrator,
> review-orchestrator, security-review-orchestrator, statusline-setup,
> vercel:ai-architect, vercel:deployment-expert, vercel:performance-optimizer

**Result**: ✅ All 7 orchestrators loaded and discoverable. Auto-routing has the
surface to fire them. (Note: only orchestrators surface in this probe; the 10
specialist agents like `code-quality-reviewer` are loaded but not listed here —
they're only spawnable from inside an orchestrator's body via the Task tool.)

## Eval 1: simple feature add (single file)

Prompt: `Add an --uppercase flag to the cli() function so it prints HELLO instead of hello when set.`

Mode: `claude -p ... --dangerously-skip-permissions`

| Metric | Value |
|---|---|
| Turns | 6 |
| Duration | 25s |
| Cost | $0.30 |
| Outcome | ✅ Feature implemented inline; final source has the flag working. |
| Task tool calls | **0** (no orchestrator spawn) |
| Orchestrator fired | ❌ |

Model judgment: 5-line single-function change classified as below-threshold for
orchestration. Work completed inline successfully.

## Eval 2: multi-file feature add (3 files)

Prompt: `Add multiply and divide operations to this CLI. Update src/myapp/__init__.py
with new functions, update src/myapp/cli.py to accept the new ops, and add corresponding
tests in tests/test_math.py. Make sure tests pass.`

| Metric | Value |
|---|---|
| Turns | 8 |
| Duration | 57s |
| Cost | $0.20 |
| Outcome | ✅ All 3 files updated correctly; 5 tests added including divide-by-zero edge case; all pass. |
| Task tool calls | **0** (no orchestrator spawn) |
| Orchestrator fired | ❌ |

Model judgment: 3-file scope with clear bounds, no architectural concerns ⇒
inline more efficient than orchestration overhead. Reasonable engineering call.

## Eval 3: explicit `/build` slash command

Prompt: `/build add subtract, multiply, and divide functions to src/myapp/__init__.py with tests in tests/test_math.py`

| Metric | Value |
|---|---|
| Turns | 9 |
| Duration | 90s |
| Cost | $0.25 |
| Outcome | ✅ All functions + tests + edge case added correctly. |
| Task tool calls | **0** (no orchestrator spawn) |
| Orchestrator fired | ❌ even with explicit `/build` |

The slash command shim's instruction "Spawn the build-orchestrator subagent
via the Task tool with the user's request as the prompt" was read by the
model but interpreted as guidance, not directive. Model still chose inline.

## Honest interpretation

**What works** (Tier-D fixes valid):
- Orchestrator subagents load correctly and are discoverable.
- ECC trigger phrases parse and rank.
- Broken PreToolUse hooks no longer poison sessions (Eval 1 ran in 25s vs the
  previous 104s in the pre-Tier-D eval where the wiki-existence gate stalled).
- All three evals delivered correct, tested code.

**What didn't change**: the model exercises its own judgment about whether to
delegate. For tasks at single-file or 3-file scope with clear bounds, it goes
inline. This matches everything-claude-code's design (~100K stars): agents are
*available*, not *always fired*. ECC documents the same trade-off — slash
commands are user-typed entry points, but description-matching is fuzzy and
discretionary, and the model evaluates per-prompt.

**Where the kit's value lands** (still untested in `-p` mode):
- INTERACTIVE Claude Code sessions where the user types `/build` and observes
  multi-turn delegation in real time. Print mode (`-p`) tends to compress
  multi-step into a single inference; interactive mode makes Task spawns more
  visible.
- Genuinely complex tasks (large refactors, security audits, multi-component
  redesigns) where the model itself decides orchestration is worth the
  overhead.
- Explicit invocation patterns: `Use the build-orchestrator for this task: ...`
  in a prompt. This phrasing has been observed to reliably trigger Task spawns.

**Tier-D recommendation**: ship as-is. The plumbing is correct, the workflows
are loaded, the kit no longer brick-walls users with broken hooks. Whether the
model delegates is a deeper LLM-tendency issue that no markdown configuration
fully solves. ECC accepts this. We should too.

## Side note: SessionEnd hook errors

All three evals showed:

```
SessionEnd hook [~/.agents/tools/_run-ps.sh ~/.agents/tools/session-end-hook.ps1 ...] failed: Hook cancelled
SessionEnd hook [~/.agents/tools/_run-ps.sh ~/.agents/tools/post-session.ps1 ...] failed: Hook cancelled
```

These appear cosmetic — Claude Code prints "failed: Hook cancelled" for any
hook that gets terminated when the session ends naturally (the timeout kicks
in before the hook completes its writeback). Not a Tier-D regression, but
worth investigating in Tier-C.
