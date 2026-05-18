# Architecture — Caspar Bannink Agentic Coding Kit

Cross-cutting system architecture, boundaries, and dependency rules.
Updated 2026-05-18.

## Layer model

```
┌──────────────────────────────────────────────────────────────┐
│  User / IDE / Terminal                                       │
├──────────────────────────────────────────────────────────────┤
│  Host Adapters                                              │
│  (claude-code, opencode, codex-cli, copilot-cli, generic)   │
├──────────────────────────────────────────────────────────────┤
│  Shared Workflow Commands                                   │
│  (build, goal, review, analyze, investigate, refactor,      │
│   redesign, security-review, plan, bootstrap-harness)      │
├──────────────────────────────────────────────────────────────┤
│  Global Skills + Agent Definitions                          │
│  (orchestrators, reviewers, specialists, prompt-synthesizer)│
├──────────────────────────────────────────────────────────────┤
│  PowerShell Tool Layer                                       │
│  (lifecycle, evidence, memory, hooks, reflection,          │
│   compression, bloat-guard, model-selector, slop-detect)   │
├──────────────────────────────────────────────────────────────┤
│  Per-repo Scaffold (.kit/, .wiki/)                          │
│  (memory, handoffs, reflections, wiki docs)                │
└──────────────────────────────────────────────────────────────┘
```

## Key directories (what gets installed)

```
~/.agents/                         # Device-wide shared brain
├── skills/                        # 24+ cross-repo skills (SKILL.md + memory.md)
├── tools/                         # 47+ PowerShell scripts
│   ├── hooks/                     # Protocol-layer enforcement (5 hooks)
│   └── *.ps1                      # Classifiers, gates, runners, validators
├── context/                       # Global reflections, memory, proposals
└── workflows/                     # gstack + superpowers + caspar-workflows

<bundled-clone>/                   # Per-repo installation target
├── .kit/                          # Repo-local harness
│   ├── context/                   # memory.md, handoffs.md, history.md, reflections.md
│   ├── agent-memory/              # Per-role specialist memory
│   ├── workflows/                 # build.md, analyze.md, review.md, investigate.md, shared.md
│   ├── modes/                     # Mode profile overrides
│   └── skills/                    # Repo-scoped skill overrides
└── .wiki/                         # Per-repo documentation
    ├── features.md                # User-visible capabilities
    ├── architecture.md            # System architecture
    ├── codebase.md                # Code layout and conventions
    └── index.md                   # Wiki entry point
```

## Source of truth layout (kit development repo)

```
bundle/
├── global/.agents/
│   ├── skills/                    # Canonical skill definitions (SSOT)
│   │   ├── build/SKILL.md
│   │   ├── goal/SKILL.md          # NEW — goal orchestrator loop
│   │   ├── plan/SKILL.md
│   │   ├── review/SKILL.md
│   │   ├── analyze/SKILL.md
│   │   ├── investigate/SKILL.md
│   │   ├── refactor/SKILL.md
│   │   ├── redesign/SKILL.md
│   │   ├── security-review/SKILL.md
│   │   ├── memory-review/SKILL.md
│   │   ├── test-gen/SKILL.md
│   │   └── [other skills]
│   ├── tools/                    # PowerShell tool implementations
│   └── context/                  # Protocol files, skill-memory-index template
├── adapters/
│   ├── _shared/
│   │   ├── workflow-commands/     # Canonical workflow phase definitions
│   │   ├── workflow-agents/       # prompt-synthesizer, slop-refactorer
│   │   └── AGENT-INSTRUCTIONS.md
│   ├── claude-code/              # CLAUDE.md, .claude/agents/, .claude/commands/
│   ├── opencode/                 # AGENTS.md, .opencode/agents/
│   ├── codex-cli/                # AGENTS.md, .codex/agents/
│   ├── copilot-cli/              # .github/agents/, .github/hooks/, copilot-instructions.md
│   └── generic/                  # AGENTS.md (fallback for Aider/Cline/Cursor/etc.)
└── repo-template/                # What gets dropped into each target repo
    ├── .kit/
    └── .wiki/
```

## Three-layer skill resolution (priority order)

1. **Repo-scoped `.kit/skills/`** — repo-specific override
2. **Global `~/.agents/skills/`** — canonical skill definition (SSOT)
3. **Shared `bundle/adapters/_shared/workflow-commands/`** — detailed phase definitions referenced by skills

Adapter-specific skill files in `bundle/adapters/*/` are thin wrappers that reference the global SSOT.
The global SKILL.md files are no longer hollow — they contain the full phase definitions.

## Orchestration models by host

| Host | Model |
|---|---|
| Claude Code | Main session coordinates, delegates to subagents via Task tool |
| OpenCode | Main session coordinates, delegates to subagents via Task tool |
| Copilot CLI | Main session IS the orchestrator, spawns only leaf agents inline with progress output |
| Codex CLI | Inline execution |
| Generic | Manual lifecycle management |

## Goal orchestrator — convergence loop

```
CLASSIFY goal type (CODE / DESIGN / INVESTIGATION / REFACTOR / MULTI)
    │
    ▼
SELECT toolchain based on type
    │
    ├─ CODE     → explore → implement → review → verify → goal-reviewer → final-verifier
    ├─ DESIGN   → aesthetic-director → playwright-navigator → playwright-runner
    │                    → ux-driver → ui-driver → visual-diff → goal-reviewer
    ├─ INVESTIGATION → investigate-orchestrator (hypothesis loop)
    ├─ REFACTOR → consequence-trace → implement → behavior-equivalence → modularity → iron-law
    └─ MULTI    → combination of above

CONVERGENCE LOOP (cap 6 iterations, hard cap 12)
    │
    ├─ stuck detection     — 3 same-signature failures → escalate
    ├─ rollback detection — same rollback triggered twice → escalate
    └─ lateral-drift      — goal diverges across iterations → re-plan

PHASE 6.5 — goal-reviewer (independent semantic verification)
PHASE 7   — final-verifier (Iron Law: fresh exit-0 evidence)
```

## Agent inventory

**Workflow agents** (5): workflow-explorer, workflow-implementer, workflow-reviewer, workflow-skeptic, workflow-ui-qa

**Specialist agents** (10): code-quality-reviewer, security-reviewer, modularity-expert, adversarial-reviewer, final-verifier, qa-reviewer, spec-reviewer, playwright-navigator, ux-driver, ui-driver

**Orchestrators** (2): goal-orchestrator, pr-reviewer

**Utility agents** (3): prompt-synthesizer, slop-refactorer, goal-reviewer

## Self-improvement loop

```
post-session.ps1 fires 11 failure detectors
    │
    ├─ tier overridden, false-positive skipped, verification gate marked
    ├─ workflow-evidence missing, bloated handoff, agent cap exceeded
    ├─ agent state mismatch, required gates incomplete, repeated task
    └─ long session >8h
         │
         ├─ PHASE 1: auto-consolidate (mechanical, REPO-level)
         │     dedup → archive promoted → drop stale → promote additive patterns
         ├─ PHASE 2: compress-memory
         │     archive old sessions → age history → dedup files → soft-limit warnings
         ├─ PHASE 2b: harness-propose (KIT-level, never auto-applies)
         │     5+ recurring patterns → proposal markdown → human review
         └─ PHASE 3: reflect-trigger
               <3 silent / 3-4 soft warn / 5+ mandatory /reflect
```

## Memory routing — 4 buckets

| Bucket | Target | Use when |
|---|---|---|
| `REPO-FACT` | `.kit/context/memory.md` | Durable repo architecture, schema, verified commands |
| `REPO-SPECIALIST` | `.kit/context/agent-memory/{role}.md` | Repo-local guidance for one specialist role |
| `SKILL-PATTERN` | `~/.agents/skills/{skill}/memory.md` | Cross-repo workflow pattern with recurring evidence |
| `SESSION-ONLY` | `${AGENTS_SESSION_ROOT}/{id}/handoffs.md` | Task progress, scratch, session-private notes |

## Verification model

**Iron Law**: no completion claims without fresh test/build/lint evidence.
Enforced mechanically by `workflow-evidence.ps1` gates + `post-session.ps1` detector.
Test commands auto-mark the verification gate via protocol-layer hooks.

## Wiki system

- **Root `.wiki/`** — development instance (used when working on the kit itself)
- **`bundle/repo-template/.wiki/`** — canonical source that gets installed into user repos
- **`~/.agents/context/`** — device-wide kit memory (global reflections, proposals)

Use `/wiki-init` to bootstrap a new repo's wiki from the repo-template version.