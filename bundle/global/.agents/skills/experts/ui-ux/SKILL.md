---
name: ui-ux-expert
description: >
  Two-agent UI/UX specialist pair. Invoke during /build when any UI component, page,
  flow, or onboarding step is being added or changed. The strategist critiques UX and
  the implementer critiques visual/component structure. Both self-reflect to global reflections.
  Uses Stitch MCP for design generation when available.
  NOTE: gemini-3.1-pro removed — CLI bug #1703. Strategist falls back to a premium reasoning model.
---

# UI/UX Expert — Two-Agent Discipline

## When to invoke

Trigger this expert when a build, refactor, or review involves any user-visible change:
- Any new React component (page, modal, form, card, badge, table)
- Any user flow change (onboarding steps, navigation, routing, redirects)
- Any visual hierarchy or information architecture change
- Any feedback/error/loading/empty state
- Any accessibility-sensitive area (keyboard nav, screen readers, color contrast)
- Any CLI output or API response that surfaces directly to end users

**Route by change semantics, not file extension** — a new API error message is a UX concern even if it lives in a `.ts` file.

Skip for: backend-only changes with no user-visible effect, test-only changes, type/schema-only changes with no behavioral surface.

---

## Agent 1 — UX Strategist

**Role**: Review the user experience — not the code.

Ask:
1. **User flow** — can the user complete the task without friction? Are there dead ends or confusing transitions?
2. **Information hierarchy** — is the most important information visible first? Is anything buried?
3. **Mental model** — does the UI match what the user expects based on common patterns?
4. **Error states** — what does the user see when things fail? Is the error actionable?
5. **Loading states** — are there skeleton screens or spinners? Does the UI feel responsive?
6. **Onboarding** — for first-time users, is the path obvious? Are there empty states?
7. **Accessibility** — keyboard navigation, focus management, screen reader labels, color contrast.

Output format:
```
UX-FINDING: [severity: critical/high/medium/low]
FLOW: [which user flow is affected]
WHAT: [one sentence — what the UX problem is]
WHY: [one sentence — why it creates friction or confusion]
FIX: [one sentence — what would resolve it]
```

---

## Agent 2 — UI Implementer
**MCP**: Stitch MCP available for design generation

**Role**: Review the component structure and visual implementation.

Ask:
1. **Component boundaries** — is each component doing one thing? Any inline component definitions (Gate #12 violation)?
2. **Prop drilling** — are props being passed more than 2 levels deep without context?
3. **Tailwind consistency** — do spacing, typography, and color tokens match existing patterns?
4. **Responsive** — does the layout work at mobile, tablet, and desktop breakpoints?
5. **State management** — is UI state (open/closed, selected, loading) co-located appropriately?
6. **Reusability** — should this be a shared component or does it need a variant of an existing one?
7. **Design generation** — use Stitch MCP to generate or validate visual designs when the plan involves new screens.

**Stitch MCP usage**: when the plan introduces a new page or significant UI section, invoke Stitch MCP to:
- Generate a reference design for the component
- Validate that the implementation matches the intended visual hierarchy
- Produce a design critique grounded in visual output (not just code reading)

Output format:
```
UI-FINDING: [severity: critical/high/medium/low]
COMPONENT: [which component or file]
LINE: [approximate line]
WHAT: [one sentence — what the implementation issue is]
WHY: [one sentence — why it matters]
FIX: [one sentence — what to change]
```

---

## Self-Reflection Protocol

After both agents complete, the orchestrator:
1. Collects all FINDING entries
2. Identifies any pattern that appeared in 2+ places (e.g., "inline component definition" appearing in multiple files)
3. Appends confirmed cross-repo UX/UI patterns to `~/.agents/context/reflections.md`:
   ```
   - [DATE]: ui-ux-expert, [pattern description], [suggested global gate or rule]
   ```
4. These patterns are picked up by `/reflect` and promoted to the appropriate skill file

---

## Integration with /build

In the `/build` Phase 7 (Final Validation), invoke the ui-ux expert when:
- The diff adds or changes any `.tsx` component file
- The plan description mentions "page", "modal", "form", "onboarding", "UI", "view"

Pass to each agent:
- The full diff or the list of changed component files
- The relevant `memory.md` and `handoffs.md` for context
- Path to this SKILL.md: `~/.agents/skills/experts/ui-ux/SKILL.md`

---

## Model Routing

| Agent | Model | Provider | Rationale |
|-------|-------|----------|-----------|
| UX Strategist | `gemini-3.1-pro` | Google | Gemini's multimodal training excels at visual/spatial/layout reasoning — best available for UX |
| UI Implementer | `(balanced model)` | Anthropic | Component structure review + Stitch MCP integration |
| **Fallback if Gemini unavailable** | `(premium reasoning model)` | Anthropic | Nearest alternative for deep UX reasoning |

---

## Notes

- These agents use **cross-provider pairing** (Google + Anthropic): Gemini's visual training challenges assumptions Claude would make on layout and UX. This is ensemble diversity even within the UI/UX domain.
- If the UI change is security-sensitive (login forms, credential input, auth flows), also invoke the `security` expert in parallel.
- Use Stitch MCP for design generation: when the plan introduces a new page or significant UI section, have the UI Implementer invoke Stitch MCP to generate a reference design, validate visual hierarchy, and produce design-grounded critique.
