---
name: redesign
description: Use when the user asks to redesign, greenfield UI, multi-component visual refresh, or fresh look. Runs aesthetic lock, current-state capture, per-component design, implement, visual-diff verification.
---

# /redesign

Multi-component visual work. Swarm-eligible when scope has 3+ independent screens/components.

## Phase 1 — Aesthetic lock

Check for `DESIGN.md` in the repo root. If it exists, read it. If it does not exist, run the `aesthetic-director` skill: it proposes 2-3 named directions (Swiss Minimalism, Editorial, Brutalism, Glassmorphism, Dark OLED Luxury, etc.), user picks one, and it writes a locked `DESIGN.md` with typography, OKLCH palette, density, motion, and a banned-defaults list.

Do NOT skip this phase. Without a locked direction, parallel design agents converge on Inter + purple gradient + rounded cards.

## Phase 2 — Current-state capture

Start the dev server: `pwsh ~/.agents/tools/dev-server-runner.ps1 -RepoRoot .`

If target routes are not yet mapped in `.agents/screen-flows.yaml`, spawn `playwright-navigator` to discover route + auth + stable selectors.

Capture before-screenshots: `pwsh ~/.agents/tools/playwright-runner.ps1 -Mode before -Screens <list>`

## Phase 3 — Per-component design

For each screen/component in scope:
- **TARGETED polish** (1-2 components): spawn `design-driver` with DESIGN.md, before-screenshot, and the specific component.
- **FULL redesign** (3+ components): spawn `ux-driver` FIRST. If `structure_ok=false`, loop on structure before any visual work. Only when `structure_ok=true`, spawn `ui-driver` for visual polish.

Cap parallel design agent spawns at ~8. Use a swarm if more.

## Phase 4 — Prompt synthesis (before implementer)

Spawn `prompt-synthesizer` with: consolidated design proposals from all design agents, `DESIGN.md` contents, before-screenshot pointers, target screens/components, target type "implementer". Use its `PROMPT_SYNTHESIS` output.

## Phase 5 — Implementation

Spawn `workflow-implementer` with the synthesized prompt from Phase 4. Give it the exact aesthetic constraints so it doesn't drift from the locked direction.

Mark gate: `pwsh ~/.agents/tools/state-gate.ps1 -SessionId "<id>" -Mark "implementation_done"`

## Phase 6 — Visual diff

Capture after-screenshots: `pwsh ~/.agents/tools/playwright-runner.ps1 -Mode after -Screens <same list>`

Run visual diff: `pwsh ~/.agents/tools/visual-diff.ps1 -Before <dir> -After <dir>`

If unintended regressions appear on screens NOT in scope: surface to user. Do not suppress.

## Phase 7 — Verification

Run the project's build/lint command. Spawn `final-verifier`. Visual regression check passes if no unintended regressions found. Run writeback.

## Phase 8 — Handoff

Include before/after screenshot pointers and visual-diff report in the summary.
