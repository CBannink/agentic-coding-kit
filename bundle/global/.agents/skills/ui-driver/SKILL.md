---
name: ui-driver
description: Screenshot-based UI critic — judges typography, color, spacing, density, motion, and AI-slop visual patterns of a running UI. Runs AFTER ux-driver gives structure_ok=true. Emits one concrete change at a time and pairs with visual-diff for verification. Successor to design-driver for the visual pass.
---

# UI Driver Skill

The agent that **looks at a screenshot and asks "does it look right?"** —
after `ux-driver` has confirmed the structure is sound.

This is the visual layer: the skin over the bones UX laid out. Critique
typography, color, spacing, density, motion, and AI-slop patterns. Do NOT
re-litigate hierarchy or flow — that's ux-driver's job, already done.

## Preconditions

The orchestrator must have run `ux-driver` and received `structure_ok=true`.
If the structure is wrong, polishing is waste. If you receive a screenshot
without an upstream UX verdict, request one before critiquing.

## Inputs

- screenshot(s) of the current state (from `playwright-explorer`)
- the upstream `UX-VERDICT` block confirming structure_ok=true
- design system / tokens / `DESIGN.md` — the **locked aesthetic direction**. The `banned-defaults` list in DESIGN.md is load-bearing for visual critique: a finding "uses `rounded-2xl` shadows everywhere" only matters if DESIGN.md says rounded-2xl is banned. If DESIGN.md is missing on greenfield UI, recommend the orchestrator run `aesthetic-director` (skill: `~/.agents/skills/aesthetic-director/SKILL.md`) first rather than critiquing against generic taste.
- `~/.agents/context/design-references.md` — visual patterns from reference systems
- the user's brief (style direction, constraints)

## Output contract

The driver does NOT silently apply changes. It emits, in order:

1. **Critique** — what's visually wrong, by category:
   - typography / readability
   - color / contrast / a11y (numeric — measure ratios)
   - spacing / alignment / rhythm
   - density / whitespace
   - motion / interaction quality
   - visual system consistency (radii, shadows, weights)
   - AI-slop patterns (see list below)
2. **Proposed change** — one concrete change, with file paths and exact
   selectors / class names / token names.
3. **Expected visual delta** — what the after-screenshot should differ.
4. **Verification plan** — which screen / flow to re-screenshot.

```
UI-FINDING: [severity: critical/high/medium/low]
SCREEN: [which screen / route]
CATEGORY: [typography | color | spacing | density | motion | system | slop]
WHAT: [one sentence — the visual problem, measured where possible]
WHY: [one sentence — why it matters]
FIX: [file path + selector/token — one concrete change]
EXPECTED-DELTA: [what the diff should show]
REFERENCE: [optional — closest analog in design-references.md]
```

## The "one change at a time" rule

The driver MUST emit one change per iteration. Reasons:
- design choices are interdependent — bundling 5 changes means you can't tell
  which made it better
- visual diffs are easier to read with a single change isolated
- it forces the driver to defend each change rather than hide marginal calls
  in a bundle

If N changes are needed, queue N-1 and emit change 1. The harness re-spawns
after the after-screenshot is captured.

## Critique vocabulary

Use specific, measurable terms. Banned vague words: "nicer", "cleaner",
"more modern", "professional", "polish".

Specific replacements:
- "the heading and subheading have similar weight (600 vs 500), breaking visual hierarchy"
- "row spacing is inconsistent: 12px between rows 1-3, 18px between 3-4"
- "primary CTA contrast is 3.2:1, fails WCAG AA for body-size text (needs ≥4.5:1)"
- "card border-radius varies (12px on dashboard, 16px on settings) — pick one"
- "icon set mixes Heroicons outline and Phosphor — pick one"

## AI-slop patterns to catch

Common signs an interface was generated rather than designed:
- gradient backgrounds on every card
- shadow on every container
- 6+ different border radii in one product
- emoji used as functional icons
- glassmorphism applied uniformly without purpose
- 12+ accent colors with no system
- center-aligned long-form text
- iconography bolted onto every menu item
- forced symmetry where information is asymmetric
- equal weight for primary and secondary actions
- pill-shaped buttons mixed with rectangular at the same level
- 3+ font families on one screen

Flag these explicitly with category `slop`. Don't just say "looks AI-generated".

## Reference reading

Before critiquing, read `~/.agents/context/design-references.md` and identify
the **closest visual analog** for the screen type. Cite it in findings — e.g.
"Stripe Dashboard's table density is the right reference here; current is 1.6x
looser without justification".

## Edits the driver may propose

- token-level: color tokens, spacing scale, type scale, radius scale, shadow scale
- component-level: button variants, card layouts, form structure
- visual-system-level: consistent radii / weights / contrast / motion timings
- a11y-level (numeric): contrast ratios, focus rings, target sizes, motion-prefers-reduced

## Edits the driver may NOT propose

- changes to `.wiki/features.md` (contract, not visual)
- changes to information hierarchy or flow (that's ux-driver's territory)
- changes to backend / API / data shape
- changes that remove functionality

If the visual problem can only be fixed by changing structure, emit a
`STRUCTURE-FEEDBACK` block and stop. The orchestrator returns to ux-driver.

## Sequential vs parallel

**Sequential (default for targeted polish)**: one ui-driver, one screen, one
change at a time. Alternates with playwright-explorer (capture → critique →
fix → recapture).

**Parallel (in `/redesign`)**: one ui-driver per screen / component, all run
concurrently against the same baseline. The synthesizer merges per-screen
plans into a coherent design system update (token changes, shared variants).

## Verification

Every emitted change must be paired with a verification step:

```yaml
- {kind: shot, label: <change_id>_after}
```

Then `visual-diff.ps1` confirms the diff is non-trivial AND limited to the
intended screen / region. Unintended changes elsewhere = regression, revert.
