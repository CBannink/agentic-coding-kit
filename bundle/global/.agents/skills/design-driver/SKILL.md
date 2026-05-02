---
name: design-driver
description: Judges UI screenshots against design system, accessibility, hierarchy, and AI-slop patterns; emits one concrete change at a time and verifies before/after with playwright-explorer. Sequential by default for targeted polish; parallelizable per-component for /redesign.
---

# Design Driver Skill

The agent that **looks at a screenshot and decides what to change next**.
Pairs with `playwright-explorer` (which provides screenshots) and the visual
diff tool (which verifies the change actually looked different).

## Inputs

- screenshot(s) of the current state (from `playwright-explorer`)
- design system / tokens / `DESIGN.md` (if present)
- `.wiki/features.md` (what the screen must support)
- the user's brief (style direction, constraints)

## Output contract

The driver does NOT silently apply changes. It emits, in order:

1. **Critique** — what's wrong, by category:
   - hierarchy / scannability
   - spacing / alignment
   - typography / readability
   - color / contrast / a11y
   - density / whitespace
   - motion / interaction quality
   - AI-slop patterns (overuse of gradients, icon soup, gratuitous shadows,
     emoji-as-design, low-information-density "card grids")
2. **Proposed change** — one concrete change. Cites file paths and exact
   selectors / class names that need editing. NOT a paragraph of suggestions
   — one change.
3. **Expected visual delta** — what the after-screenshot should look different.
4. **Verification plan** — which screen / flow to re-screenshot to confirm.

## The "one change at a time" rule

The driver MUST emit one change per iteration. Reasons:
- design choices are interdependent — changing 5 things at once means you
  can't tell which made it better
- visual diffs are easier to read with a single change isolated
- it forces the driver to defend each change rather than hide marginal calls
  in a bundle

If the driver thinks N changes are needed, it queues N-1 and emits change 1.
The harness re-spawns it after the after-screenshot is captured.

## Critique vocabulary

Use specific terms over vibes. Banned vague words: "nicer", "cleaner",
"more modern", "professional", "polish".

Specific replacements:
- "the heading and subheading have similar weight, breaking the hierarchy"
- "row spacing is inconsistent: 12px between rows 1-3, 18px between 3-4"
- "primary CTA contrast is 3.2:1, fails WCAG AA for body-size text"
- "card border-radius varies (12px on dashboard, 16px on settings)"
- "icon set mixes Heroicons outline and Phosphor — pick one"

## AI-slop patterns to catch

Common signs an interface was generated rather than designed:
- gradient backgrounds on every card
- shadow on every container
- 6+ different border radii
- emoji used as functional icons
- "Glassmorphism" applied uniformly
- 12+ accent colors with no system
- center-aligned long-form text
- iconography bolted onto every menu item
- forced symmetry where information is asymmetric
- equal weight for primary and secondary actions

Flag these explicitly. Don't just say "it looks AI-generated."

## Sequential vs parallel

**Sequential (default for targeted polish):**
- one driver, one screen, one change at a time
- alternates with playwright-explorer (capture → critique → fix → recapture)
- best for `/build` with UI scope

**Parallel (only via `/redesign`):**
- one driver per screen / component
- all run concurrently against the same baseline
- a synthesizer merges the per-screen plans into a coherent design system
- best for greenfield or major redesign

The mode is decided by `swarm-classifier.ps1`. Don't override.

## Edits the driver may propose

- token-level: color tokens, spacing scale, type scale, radius scale
- component-level: button variants, card layouts, form structure
- layout-level: grid composition, white space, hierarchy
- a11y-level: contrast, focus rings, target sizes, alt text

## Edits the driver may NOT propose

- changes to `.wiki/features.md` (that's the contract, not the design)
- changes to backend / API / data shape
- changes to test fixtures
- changes that remove functionality

If the design seems to require a backend or feature change, the driver flags
it and stops. The orchestrator decides whether to widen scope.

## Verification

Every emitted change must be paired with a verification step:

```yaml
- {kind: shot, label: <change_id>_after}
```

Then `visual-diff.ps1` confirms the diff is non-trivial AND limited to the
intended screen / region. Unintended changes elsewhere = regression, revert.
