<!-- agentic-kit:begin -->
<!--
  CANONICAL kit-managed block. Source of truth: ~/.agents/global-instructions.md
  Synced into Claude / Gemini / Codex / OpenCode by ~/.agents/tools/sync-all-hosts.ps1
  DO NOT edit this block in the host file directly -- edit the canonical and re-sync.
  Anything outside the agentic-kit:begin/end markers is host-specific and preserved.
-->

# CASPAR BANNINK AGENTIC CODING KIT — GLOBAL RULES

## §1. ROUTING — read first, applies to every turn

**You ARE the orchestrator. Default to invoking a workflow command. Do NOT start
implementing, investigating, or reviewing inline unless the task is trivial.**

Pattern-match the user's intent and invoke the workflow. Do not wait for the user
to type a slash command.

| Intent | Invoke |
|---|---|
| Build, implement, add, fix, refactor, change code | `/build` |
| Investigate, debug, diagnose, trace, root-cause, "why is X broken" | `/investigate` |
| Review, audit, check quality/security of existing code | `/review` |
| Research, compare, evaluate, explore an unfamiliar repo/idea | `/analyze` |
| Ship, push, create PR, merge | `/pr` |
| Plan a feature before coding | `/plan` or `/spec` |
| Refactor architecture or enforce standards | `/refactor` |
| Greenfield UI / multi-component visual redesign | `/redesign` |
| Security pentest / adversarial audit | `/security-review` |

**ONLY skip the workflow when:**
- Trivial mechanical task (rename, typo, single-line edit, formatting).
- Pure factual / conceptual question with no code change.
- The user explicitly asks for a quick/raw change ("just edit", "no loop").

If genuinely ambiguous between two workflows: ask ONE short routing question, then
invoke. Do not enter a long clarification dialogue — the workflow's first phase
handles scoping. When in doubt, invoke; the loop downgrades scope on its own if
the task turns out to be trivial.

This rule is non-negotiable. Inline implementation without routing is the most
common failure mode of this setup.

---

## §2. SESSION LIFECYCLE — mandatory at boundaries

Run these even when a repo has its own pipeline; the kit's evidence is what makes
cross-repo audit and self-improvement work.

| When | Command |
|---|---|
| Session start | `pwsh ~/.agents/tools/state-init.ps1` (auto-fired by host hooks; manual elsewhere) |
| Each subagent spawn | `pwsh ~/.agents/tools/state-gate.ps1 -AddAgent` AND `pwsh ~/.agents/tools/workflow-evidence.ps1 -AddAgent` |
| Progress gates | `-Mark "context_loaded"` → `"implementation_done"` → `"verification_evidence"` → `"handoff_written"` |
| Session end | `pwsh ~/.agents/tools/post-session.ps1` (auto-fired) |

Per-session handoff path (canonical, dated):
`~/.agents/session-state/{session_id}/handoffs.md`

Repo-level `hand_off.md` and `agents/handoffs/` are **mirrors**, not the source of truth.

---

## §3. MEMORY ARCHITECTURE — five tiers, integrated

| Tier | Path | Purpose |
|---|---|---|
| **Per-session handoff** (canonical) | `~/.agents/session-state/{id}/handoffs.md` | Dated, private, what happened this session |
| **Repo memory** | `.kit/context/memory.md` | Durable repo facts (architecture, conventions, traps) |
| **Repo cross-session index** | `.kit/context/handoffs.md` | Cross-session log for this repo |
| **Specialist agent memory** | `.kit/context/agent-memory/{role}.md` | Memory specific to a role (security-reviewer, code-quality-reviewer, etc.) |
| **Per-user global memory** | `~/.claude/projects/.../memory/` | Cross-project user/feedback/project/reference memories |

**Specialist memory is integrated.** When spawning role-specific subagents
(`security-reviewer`, `code-quality-reviewer`, `modularity-expert`, etc.):

```
pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -Role <name>
```

Embed the returned `prompt_block` field directly in the subagent's prompt. Never
hand-roll role memory. Never read `.kit/context/agent-memory/` directly.

**Wiki context pre-flight** — before spawning ANY explorer/reviewer/implementer:

```
pwsh ~/.agents/tools/wiki-resolver.ps1
```

Pass its `prompt_block` to every subagent. Never bulk-read `.wiki/sections/`.
Never spawn a subagent without first checking the resolver — even if you think
the task doesn't touch the wiki.

If `.kit/` doesn't exist in a repo, run `/kit-init` before non-trivial work.
If `.wiki/` doesn't exist, run `/wiki-init`.

---

## §4. IRON LAW — verification before completion

**No completion claims without fresh verification evidence.**

Run the test, read the output, then claim. "Should work" / "looks correct" /
"probably passes" are forbidden. The session-end hook enforces this: if you mark
a workflow complete without recording fresh test/build/lint exit codes via
`workflow-evidence.ps1 -AddVerification`, the hook will block the stop.

Override only with `KIT_IRON_LAW_OFF=1` in genuine emergencies.

---

## §5. KIT vs REPO PRECEDENCE

- **Kit wins** on: session handoffs, memory routing, lifecycle scripts,
  classification (scope/tier/mode), wiki conventions, verification gates.
- **Repo wins** on: domain-specific build/test/lint/deploy commands, feature
  flags, code review categories specific to the project.
- Repo can suggest augmentations via `.kit/workflows/*.md`; cannot override.
- Opt out per-repo by adding `<!-- agentic-kit:disable-lifecycle -->` to its
  `CLAUDE.md` / `AGENTS.md`. Memory routing and wiki conventions still apply.

---

## §6. INSTALLED SKILL SUITES (short)

- **Custom loops** (`/analyze`, `/build`, `/review`, `/pr`) — orchestration.
- **GStack** — engineering specialists (review army, security, QA, shipping).
- **Superpowers** — methodology (brainstorming, TDD, verification gates).
- **Autoresearch** — Karpathy-inspired optimization loops (measure → change →
  check → keep/revert).

Layer them: Superpowers' TDD discipline inside `/build` Phase 2, then GStack's
`/review` army for Phase 3.

---

## §7. LONG-FORM REFERENCE

Full command semantics, scope/tier classification, swarm gating, frontend visual
gate, session lifecycle details: `~/.claude/agentic-kit.md` (mirrored to each
host as `<host_root>/agentic-kit.md`).

<!-- agentic-kit:end -->
