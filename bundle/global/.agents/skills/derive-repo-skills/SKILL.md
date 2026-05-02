---
name: derive-repo-skills
description: >
  Repo bootstrap workflow that derives repo-specific skills and a routing index from repo
  evidence. Combines work-surface discovery, git-backed convention extraction, current-code
  confirmation, scoped evidence judgment, and repo-local skill synthesis so later agents can
  load only the repo guidance they actually need.
---

# Derive Repo Skills

## What this skill does

This skill turns a new or unfamiliar repository into an **evidence-backed repo onboarding pack**.

It does **not** guess conventions from one file. It gathers evidence from:
- repo structure and stack signals
- git history and reverts
- current source implementations
- existing docs/context when present

Then it produces:
1. a machine-readable routing index
2. a human-readable repo conventions profile
3. a small set of **high-confidence** repo-specific skill files worth loading later

The index and profile are the primary durable outputs.
Generated skill files are secondary and should be rarer.

---

## When to Invoke

- First serious session in an unfamiliar repo
- When `.codex/skills/index.json` is missing
- When repo conventions are unclear or spread across history + current code
- After major architecture or stack changes that may invalidate old repo-local guidance
- Before repeated `/build` or `/review` work in the same repo when onboarding cost is high

## When NOT to Invoke

- Small one-off fixes in a repo you already understand
- Repos with too little history to establish stable patterns
- Situations where a single `git-archaeology` pass is enough for the current session
- As a substitute for `/build`, `/analyze`, `/review`, or `/investigate`

---

## Core Principle

**Global skills provide process discipline. Repo-local skills provide local conventions.**

This skill owns the translation between those two layers.

Default mode is **full derive**.

An explicitly bounded **scoped derive** is allowed only when refreshing one or more named surfaces inside an existing onboarding pack. Scoped derives must stay surface-local; if the evidence points to repo-wide or cross-surface convention drift, escalate back to a full derive instead of stretching the scope silently.

---

## Load Context First (graceful — skip missing files)

Read these when they exist:
- `AGENTS.md`
- `CLAUDE.md`
- `GEMINI.md`
- `.wiki/features.md`
- `.codex/context/memory.md`
- `.codex/context/history.md`
- `.codex/context/handoffs.md`
- existing `.codex/skills/index.json`
- existing `.codex/skills/profile.md`

Use them as evidence sources, not as unquestioned truth.

Schema reference for the canonical routing artifact:
- `~/.agents/context/repo-skills-index.schema.json`

---

## Agent Matrix

### Explore

- `repo-triage-explorer`
  Purpose: detect repo shape, work surfaces, execution affordances, likely ownership boundaries, and the vocabulary this repo actually uses.
  Model: `(premium reasoning model)`

- `history-patterns-explorer`
  Purpose: run `git-archaeology` or equivalent history extraction to get naming, file placement, testing, and revert-backed antipatterns when history is informative.
  Model: `(premium reasoning model)`

- `current-patterns-explorer`
  Purpose: inspect representative current modules and entrypoints chosen from discovered work surfaces to confirm how the repo works now, not only how it evolved before.
  Model: `(premium reasoning model)`

### Synthesize

- `relevance-judge`
  Purpose: decide which evidence-backed claims are promotable into repo-local skills versus profile-only guidance.
  Model: `(premium reasoning model)`

- `skill-synthesizer`
  Purpose: generate the repo-local profile, routing index, and derived skill files from the verified evidence packet and promotion decisions.
  Model: `(premium reasoning model)`

### Verify

- `claim-verifier`
  Purpose: verify that every generated repo-local skill and routing rule is backed by specific evidence and that no low-confidence claim was promoted.
  Model: `(balanced model)`

---

## Workflow

## Inter-Phase Handoff Contract

The derive workflow uses three **session-private** handoff artifacts between sub-agents:

1. **Surface Evidence Matrix** — explorers -> `relevance-judge`
2. **Evidence Packet** — explorers + matrix -> `relevance-judge` -> `skill-synthesizer`
3. **Promotion Decisions** — `relevance-judge` -> `skill-synthesizer` -> `claim-verifier`

These are orchestration artifacts only. They are **not** durable repo-local outputs and **must not** be read by `/build`, `/review`, or `/analyze`.

### Surface Evidence Matrix (session-private)

For each discovered surface, capture:
- `surface_id`
- `surface_type`
- `paths`
- `representative_package_or_config`
- `representative_current_code`
- `representative_test_or_verification_entry`
- `history_signal_quality`
- `current_signal_quality`
- `docs_signal_quality`
- `verdict` (`strong`, `partial`, `unclear`)

### Evidence Packet (session-private)

For each candidate repo claim, capture:
- `claim_id`
- `surface_id`
- `claim_type` (`placement`, `naming`, `testing`, `routing`, `library-choice`, or similar)
- `scope` (`repo-wide`, `surface`, `package`, `path-family`, or similarly narrow scope)
- `supporting_evidence`
- `contradicting_evidence`
- `source_quality` (`history`, `current_code`, `docs`) each marked `strong`, `partial`, `sparse`, or `unavailable`
- `applicability_boundary`
- `unknowns`

### Promotion Decisions (session-private)

For each `claim_id`, capture:
- `decision` (`promote`, `profile-only`, `reject`)
- `reason`
- `target_artifact`
- `load_when`
- `why_global_skills_are_insufficient`

### Consumer Handoff (durable)

Downstream workflows consume only these durable repo-local artifacts:
1. `.codex/skills/index.json` — canonical machine-readable router
2. `.codex/skills/profile.md` — canonical human-readable evidence summary
3. `.codex/skills/generated/*.md` — optional generated skills referenced by the index

Consumers load the index first, then the profile, then only the referenced generated skills that are both relevant and high-confidence.

### Derive Modes

- **full** — default onboarding pass for the whole repo; safe place to derive repo-wide guidance when evidence supports it
- **scoped** — targeted refresh for one or more named surfaces only; may update only surface-bounded guidance and must not be presented as repo-wide coverage

Scoped derive rules:
- name the target surfaces explicitly in the durable artifacts
- keep promoted skills bounded to those surfaces
- mark uncovered or unsampled surfaces clearly in the profile and coverage summary
- if a candidate claim crosses outside the targeted surfaces, downgrade it to profile-only or rerun as full derive

### Phase 1: Work-Surface Discovery

Establish:
- primary languages
- repo shape
- primary work surfaces (for example: UI app, service/API, library/SDK, CLI, infra/config, data pipeline, docs/content, plugin/extension, mixed)
- test framework(s)
- build tools and execution affordances
- likely ownership boundaries

Each discovered surface must be concrete enough to populate the Surface Evidence Matrix.

If the repo shape is still unclear after triage, stop and report the ambiguity instead of generating skills.

Choose a coarse adaptive sampling mode before current-code exploration:
- **minimal** — small, uniform repo; 1-2 major surfaces; low tool divergence
- **standard** — default; several clear surfaces or moderate package/tool variation
- **expanded** — heterogeneous repo; many surfaces, multiple runner/build stacks, or conflicting signals between history and current code

Sampling mode controls how many representative current examples you inspect and how much cross-surface confirmation you need before calling something stable. This is a sampling-adequacy control, not a promotion shortcut.

### Phase 2: Historical Conventions

Run `git-archaeology` (skill: `~/.agents/skills/git-archaeology/SKILL.md`) to extract a **Project Conventions Profile**.

If history is sparse, shallow, missing, or otherwise low-signal, record that explicitly in the evidence packet as `history: sparse|unavailable`. Absence of history is not evidence of any convention.

Use history to answer:
- where new files normally land
- naming conventions
- test placement and frameworks
- preferred libraries in new code
- fragile or reverted patterns to avoid

History is evidence, not destiny. It must be reconciled with current code.

### Phase 3: Current-Code Confirmation

Inspect representative implementations in the current repo chosen from the surfaces found in Phase 1.

Adaptive target:
- **minimal** — 2-3 current examples total
- **standard** — 3-5 current examples total
- **expanded** — 4-6 current examples total, with at least one example per major surface and extra confirmation where tooling diverges

For each sampled implementation:
- state which surface it represents
- state why it is representative
- record whether it confirms, narrows, or contradicts the history signal

Representative-sample heuristics:
- prefer active source-of-truth modules, entrypoints, routing roots, or package roots over leaf utilities
- prefer recently changed or repeatedly copied patterns over abandoned legacy folders
- avoid generated code, vendored code, migration leftovers, and test fixtures unless the claim is specifically about them
- for testing claims, prefer the runner/config entry plus a real current test that matches the dominant style for that surface
- when two candidate examples disagree, treat that as a scope-splitting or contradiction signal, not as something to average away

For testing or runner claims, inspect both:
- a package/config source of truth
- a representative current test file or test command entry

Goal: confirm what is **currently** idiomatic and what history may have drifted away from.

### Phase 4: Evidence Reconciliation and Scope Assignment

For each candidate claim, assign:
- `scope`
- `confidence` (`high`, `medium`, `low`)
- `source_quality`
- `applicability_boundary`
- `contradictions`
- `unknowns`

Rules:
- unresolved contradictions block promotion for that claim unless the claim can be narrowed safely to a smaller scope
- `medium` confidence means useful context may exist, but not durable skill promotion
- `low` confidence means reject the claim from durable outputs
- every claim must map back to at least one surface in the Surface Evidence Matrix

Also produce a coarse coverage summary for the durable handoff:
- `overall` (`broad`, `adequate`, `partial`)
- `sampling_mode` (`minimal`, `standard`, `expanded`)
- notable uncovered surfaces or evidence gaps

Coverage summary is advisory. It may justify more sampling, profile-only wording, or a rerun hint. It does **not** override the fail-closed promotion gate.

### Phase 4.5: Promotion Gate

Promotion is **fail-closed**.

Required evidence tuples by claim type:
- **general placement/naming/routing claim** -> at least one history signal + one current-code signal
- **cross-surface claim** -> confirming current evidence from at least two surfaces
- **testing or runner claim** -> package/config evidence + representative current test evidence; add history only when using it to justify stability

If the tuple is incomplete, the claim may be `profile-only` but must not be promoted.

### Phase 5: Relevance Judgment and Promotion

Decide which repo-local skills are justified.

A repo-local skill is justified only if the pattern is:
- repeated
- stable
- actionable for future agents
- not already covered well enough by global skills
- `confidence: high`
- required evidence tuple complete
- scope and boundaries narrow enough to be safe for future consumers

**Hard cap:** generate **no more than 5 repo-local skills** in v1.

If the evidence is weak, output:
`No high-confidence repo skills derived; use global skills + profile only.`

In that case, still write the required `index.json` and `profile.md` artifacts.
The no-op form is:
- `repo_local_skills: []`
- a note explaining that evidence was too weak to derive repo-local skills confidently

`medium`-confidence findings belong in `profile.md` only.

### Phase 6: Skill Synthesis

Write these repo-local artifacts:

1. **Required** — `.codex/skills/index.json`
2. **Required** — `.codex/skills/profile.md`
3. **Optional** — `.codex/skills/generated/*.md` for each promoted high-confidence repo-local skill

Prefer narrow skills such as:
- `repo-frontend-patterns`
- `repo-backend-patterns`
- `repo-testing-patterns`
- `repo-directory-conventions`
- `repo-naming-conventions`

Do **not** generate giant omnibus skills when smaller focused ones are clearer.

The `skill-synthesizer` consumes:
- the Surface Evidence Matrix
- the verified Evidence Packet
- the Promotion Decisions

The index and profile are the canonical durable handoff artifacts for later workflows.

Mechanical enforcement tool:
- `pwsh ~/.agents/tools/validate-repo-skills-index.ps1 -RepoRoot {target-repo-root}`
- validator verdict contract:
  - `status`: `valid` | `legacy` | `missing` | `invalid`
  - `trust_level`: `normal` | `lowered` | `blocked`
  - `recommended_action`: e.g. `load_index_routing`, `prefer_profile_and_global_skills`, `run_derive_repo_skills`, `run_scoped_derive_repo_skills`
  - `strict_failure`: `true` only when current-contract validation is required and not met
  - `loadable_skill_paths`: resolved skill files safe to load

### Phase 7: Verification

Before completion, verify:
- run `pwsh ~/.agents/tools/validate-repo-skills-index.ps1 -RepoRoot {target-repo-root} -RequireCurrentContract`
- require validator result `status: "valid"` and `strict_failure: false`
- each routing recommendation in the index is evidence-backed
- no generated skill merely restates a global skill without repo-local content
- no more than 5 repo-local skills were generated
- no generated repo-local skill has `confidence` lower than `high`
- every promoted claim has the required evidence tuple for its claim type
- every promoted claim maps cleanly to one or more surfaces in the Surface Evidence Matrix
- each generated repo-local skill referenced by `index.json` was re-read from disk and its evidence references match the Phase 2 and Phase 3 findings
- the profile clearly separates stable patterns, scoped/tentative patterns, and evidence gaps
- the index remains valid when `repo_local_skills` is empty

---

## Output Contracts

### 1. `.codex/skills/index.json`

Machine-readable routing file for later agents.

Current schema reference:
- `~/.agents/context/repo-skills-index.schema.json`

Suggested shape:

```json
{
  "schema_version": 3,
  "generated_at": "2026-04-27T09:00:00Z",
  "generator": "derive-repo-skills",
  "assurance": "evidence-backed",
  "derive_mode": "full",
  "freshness": {
    "status": "fresh",
    "basis": "generated from current repo state and recent history",
    "scope": "repo",
    "target_surfaces": []
  },
  "stack": {
    "languages": ["TypeScript"]
  },
  "repo_shape": "mixed",
  "coverage_summary": {
    "sampling_mode": "standard",
    "overall": "adequate",
    "history": "strong",
    "current_code": "adequate",
    "gaps": []
  },
  "surfaces": [
    {
      "id": "surface-ui-app",
      "type": "ui-app",
      "paths": ["apps/web"],
      "confidence": "high",
      "coverage": "adequate"
    }
  ],
  "execution_affordances": {
    "package_manager": "pnpm",
    "build": ["pnpm build"],
    "test": ["pnpm test"]
  },
  "evidence_quality": {
    "history": "strong",
    "current_code": "strong",
    "docs": "partial"
  },
  "recommended_global_skills": [
    {
      "name": "build",
      "reason": "standard implementation workflow"
    },
    {
      "name": "git-archaeology",
      "reason": "repo shows stable git-backed conventions"
    }
  ],
  "repo_local_skills": [
    {
      "name": "repo-frontend-patterns",
      "path": ".codex/skills/generated/repo-frontend-patterns.md",
      "load_when": [
        "touching React routes/components/hooks",
        "changing user-visible frontend behavior"
      ],
      "scope": "surface",
      "confidence": "high",
      "promoted_from": ["claim-frontend-routing"],
      "boundaries": [
        "applies to React route and component organization only"
      ],
      "evidence": [
        "git history",
        "current src/routes examples"
      ]
    }
  ],
  "profile_path": ".codex/skills/profile.md",
  "notes": [
    "Routing is advisory in v1; agents may fall back to global skills when evidence is weak."
  ]
}
```

`freshness.status` valid values in v1:
- `fresh` — safe to use as advisory routing
- `stale` — consumer should warn and recommend regeneration before trusting repo-local skills for non-trivial work

`freshness.scope` valid values:
- `repo` — freshness applies to the whole onboarding pack
- `surface` — freshness/rerun guidance is bounded to the listed `target_surfaces`

`derive_mode` valid values:
- `full`
- `scoped`

Mark the index `stale` in v1 when any of these are true:
- the repo's primary stack or build files changed materially since generation
- major architecture or package-boundary changes were introduced
- any generated repo-local skill path referenced by the index no longer exists

Rerun hint:
- prefer `run_scoped_derive_repo_skills` only when the drift is clearly bounded to named surfaces
- prefer `run_derive_repo_skills` when repo shape, primary tooling, or repo-wide conventions may have shifted

Consumer note: wall-clock age is consumer-owned. `/build` and `/review` should also treat `generated_at` older than 30 days as stale even if the producer last wrote `fresh`.

### 2. `.codex/skills/profile.md`

Human-readable conventions summary:
- derive mode and target surfaces
- stack and repo shape
- coverage summary and adaptive sampling mode
- stable patterns (high-confidence)
- scoped or tentative patterns (medium-confidence; verify before relying on them)
- known antipatterns and caution areas
- generated repo-local skills
- evidence gaps

### 3. `.codex/skills/generated/*.md`

Each generated skill must include:
- what work it applies to
- its scope and boundaries
- the repo-specific patterns to follow
- repo-specific antipatterns to avoid
- evidence references
- trigger conditions for loading
- where it does **not** apply

Recommended headings:
- `## Applies To`
- `## Scope and Boundaries`
- `## Patterns To Follow`
- `## Antipatterns To Avoid`
- `## Evidence`
- `## Load When`
- `## Does Not Apply`

---

## Guardrails

- **No global mutation**: never modify global skills from this workflow.
- **Repo-local only**: write outputs inside the target repo.
- **Evidence-first**: `index.json` and `profile.md` are the primary durable outputs; generated skills are secondary.
- **No skill factories**: hard cap 5 generated repo-local skills (0–5 valid; weak evidence may yield fewer).
- **Evidence or nothing**: every derived skill needs multi-source evidence.
- **High-confidence only**: only `high`-confidence claims may become generated repo-local skills.
- **Fail-closed promotion**: incomplete evidence tuples force `profile-only` or `reject`, never promotion.
- **Advisory routing in v1**: the generated index guides agents; it is not absolute truth.
- **Allow no-op output**: weak evidence is a valid result.
- **Session-private orchestration**: Evidence Packet and Promotion Decisions stay session-private; consumers must not rely on them.
- **No continuous regeneration**: regeneration is explicit and user-directed, not background automation inside another workflow.
- **No fake precision**: use coarse coverage bands and sampling modes, not numeric certainty theatre.
- **Scoped means scoped**: a scoped derive must never silently imply repo-wide freshness or repo-wide conventions.

---

## Recommended Integration

Use this skill as a **repo bootstrap**.

Then let later workflows consume its outputs:
- `/build` Phase 0 checks `.codex/skills/index.json` first, then `.codex/skills/profile.md`, then relevant generated skill files when the index points to them
- `/review` uses the same index-first handoff and treats `profile.md` as the source of caveats and uncertainty
- `/analyze` uses the profile as an evidence source and may load relevant high-confidence generated skills when the index points to them and the current question overlaps their scope

If the index is missing or stale, regenerate it explicitly with this skill.

---

## Scope Rules

- Keep v1 narrowly focused on convention extraction + routing.
- Do not invent repo-local skills for every subsystem.
- Do not treat sparse history as strong evidence.
- If history and current code disagree, record the contradiction in `profile.md` and block promotion for that claim unless it can be narrowed safely to a smaller scope.
- Do not promote `medium`-confidence patterns into generated repo-local skill files.
- Do not promote a cross-surface pattern from one sampled surface plus one guessed extension.
- Do not promote testing guidance without both package/config evidence and representative current test evidence.
- Do not use `coverage_summary` as a substitute for the promotion gate.
- Do not keep a scoped derive in `full` mode just to make the output look stronger.
