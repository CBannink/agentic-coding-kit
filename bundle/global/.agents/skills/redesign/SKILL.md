---
name: redesign
description: Greenfield UI work and multi-component visual redesign. Swarm-eligible. Combines the swarm skill with playwright-explorer (current-state capture) and design-driver (per-component visual judgment). Not for targeted feature polish — use /build for that.
---

# Redesign Skill

Use for **greenfield UI** or **multi-component redesigns** where independent
components / screens can be redesigned in parallel.

## Eligibility

All must hold:
- task verb is "redesign", "explore designs", "rebuild UI", or similar
- scope covers ≥3 independent components or screens
- there's a working local dev server (or one can be started) for screenshot capture
- the user opted in (default for `/redesign` command)

If only one component / one screen is in scope → use `/build` with the
`design-driver` skill, not this.

## Steps

### 1. Capture current state

```powershell
pwsh ~/.agents/tools/playwright-runner.ps1 -ConfigPath .agents/screen-flows.yaml -OutDir ${session_dir}/screenshots/before
```

`playwright-explorer` skill drives the runner to navigate every screen in
`.agents/screen-flows.yaml` and capture stable, full-page screenshots at
2x DPI. If `screen-flows.yaml` doesn't exist, generate one by exploring the
local dev server (see `playwright-explorer` skill).

### 2. Read existing design system

Required reads before any redesign:
- `.wiki/features.md` — what the UI must support
- any `DESIGN.md`, `design-system.md`, `tailwind.config.*`, theme files
- the current screenshots from step 1

### 3. Decompose

List the screens / components to redesign. One agent per item.

Bad decomposition example: ["fix the typography" "fix the colors" "fix the layout"]
— these touch every screen, so they collide.

Good decomposition example: ["dashboard" "settings" "profile" "onboarding flow"]
— each agent owns one surface end-to-end.

### 4. Fan out — one design-driver per item

Each `design-driver` agent receives:
- the screen's current screenshot(s)
- the design system constraints
- the user's brief
- one concrete change at a time policy

See `design-driver/SKILL.md` for the agent contract.

### 5. Capture after-state

```powershell
pwsh ~/.agents/tools/playwright-runner.ps1 -ConfigPath .agents/screen-flows.yaml -OutDir ${session_dir}/screenshots/after
```

### 6. Visual diff

```powershell
pwsh ~/.agents/tools/visual-diff.ps1 -BeforeDir ${session_dir}/screenshots/before -AfterDir ${session_dir}/screenshots/after -OutDir ${session_dir}/screenshots/diff
```

Each diff is reviewed by the synthesizer. Regressions (unintended changes)
are flagged.

### 7. Synthesize design system

One synthesizer agent reads all per-component changes and unifies them into:
- updated design tokens (color, spacing, typography)
- updated `DESIGN.md` (or creates one)
- a list of cross-component patterns that emerged

### 8. Verify

- run the app, navigate every screen manually OR via playwright-runner
- confirm no console errors, no a11y regressions
- confirm `.wiki/features.md` flows still work end-to-end

### 9. Write evidence

```powershell
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId $SessionId -Tier SWARM -TierReason "redesign + N components" -AddNote "redesign:items=<list>|before=<count>|after=<count>"
```

## Anti-patterns

- **Redesigning while shipping a feature** — separate the concerns. Do the
  redesign in its own session.
- **No before-state capture** — without baselines, regressions are invisible.
- **Skipping the synthesizer** — N independently-redesigned components ≠
  redesigned product. The synthesis IS the design system work.
- **Auto-applying changes without screenshots** — visual work must be
  visually verified.
