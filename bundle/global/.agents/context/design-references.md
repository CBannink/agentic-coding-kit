# Design References

A curated index for `ux-driver` and `ui-driver` agents. Read this before
critiquing a screen — find the **closest analog** and cite it in findings.

This file ships **abstracted patterns** (words) and **public links** (URLs).
It does NOT ship third-party screenshots. Mobbin / Refero / SaaSFrame are
inspiration sources you visit at runtime, not corpora we redistribute.

## How drivers use this

1. Identify the screen type (dashboard / list / settings / onboarding / detail / form / empty).
2. Find the matching section below.
3. Pick the closest analog from "First-party references" (safe to read fully).
4. Optionally consult "Inspiration sources" (curated public URLs).
5. Optionally invoke `design-fetcher.ps1` to capture a transient session-only screenshot.
6. Cite the analog in `REFERENCE:` field of findings.

## First-party design system docs (permissively licensed, abstract freely)

| System | URL | Strongest at | Use when |
|---|---|---|---|
| **Material Design 3** | https://m3.material.io/ | Density, motion, color systems, accessibility tokens | Android / cross-platform; needs documented motion language |
| **Apple Human Interface Guidelines** | https://developer.apple.com/design/human-interface-guidelines/ | Interaction polish, touch targets, system controls | iOS / macOS; needs platform-native feel |
| **Radix Themes** | https://www.radix-ui.com/themes/docs/overview/getting-started | Headless component composition, color scales (12 steps), a11y | React app; needs solid primitives without opinionated visuals |
| **shadcn/ui** | https://ui.shadcn.com/ | Modern web app components, copy-paste ownership, Tailwind-native | Tailwind + React; needs flexible component layer to own |
| **Vercel Geist** | https://vercel.com/geist | Developer-tool aesthetics, dense data, monospace integration | Dashboards for technical users; CLI/dev product UIs |
| **Linear method** | https://linear.app/method | Keyboard-first interaction, command palette discipline | Power-user tools; needs high information density without noise |
| **IBM Carbon** | https://carbondesignsystem.com/ | Enterprise data density, complex tables, multi-product systems | B2B / enterprise; needs to scale across many surfaces |
| **Atlassian Design System** | https://atlassian.design/ | Forms, multi-step flows, configuration-heavy apps | Settings-heavy / admin-heavy products |
| **Tailwind UI patterns** | https://tailwindui.com/components | Reference Tailwind class compositions for common patterns | Tailwind project; need a known-good class composition |
| **WAI-ARIA Authoring Practices** | https://www.w3.org/WAI/ARIA/apg/patterns/ | Keyboard interaction patterns, focus management, role semantics | Any interactive component; needs correct a11y behavior |

## Inspiration sources (link out, do not cache)

These sites curate real product UIs by pattern. Useful for ux-driver to
ground critique in working examples. Visit at runtime, do not scrape.

| Source | URL | Best for | Notes |
|---|---|---|---|
| **Mobbin** | https://mobbin.com/ | Mobile app screens + flows by pattern | Account often required; copyrighted screenshots, do not redistribute |
| **Refero** | https://refero.design/ | Curated web product references by pattern | Use for landing/marketing/dashboard inspiration |
| **SaaSFrame** | https://www.saasframe.io/ | SaaS product UI + onboarding flows | Strong for empty states, pricing pages, settings |
| **Collect UI** | https://collectui.com/ | Daily UI inspiration, gallery format | Concept work — less "real product flows" |
| **Page Flows** | https://pageflows.com/ | Recorded user flows from real apps | Best when critiquing onboarding or multi-step flow |
| **Land-book** | https://land-book.com/ | Marketing / landing page references | Use for non-app surfaces only |

## Pattern catalog (abstracted, safe to read in full)

### Dashboard

**Reference**: Stripe Dashboard, Linear inbox, Vercel deployments

Anatomy:
- Top bar: workspace switcher (left) + global search + user menu (right). Height 48-56px.
- Left nav: 220-260px, sections separated by 12px gaps, no shadows.
- Content: max-width either 1200px (Stripe) or full-bleed (Linear). Padding 24-32px from nav edge.
- Primary action: top-right of content area, NOT in nav. Single primary CTA per page.
- Data density: 7-10 fields per row in tables. Use `tabular-nums` for numbers.

Common slop: hero card on dashboards (Stripe doesn't use one), gradient on every card, action buttons in sidebar.

### List view (the Incogniton case)

**Reference**: Linear issues, GitHub PRs, Stripe customers, Notion table

Anatomy:
- Filter / search bar above list, sticky on scroll. Inline filter chips, not modal.
- Row: avatar/icon + primary identifier + 2-4 metadata fields + status indicator + action menu (right).
- Row height: 40-48px (compact) or 56-72px (comfortable). Pick one — never mix.
- Status: text or icon, not gradient pills.
- Bulk actions: appear in a toolbar above the list when ≥1 row is selected.
- Empty state: single sentence + primary CTA, centered. No illustration unless brand-mature.

Density target: 12-20 visible rows on a 1080p viewport.

Common slop: 3-line rows for 2 fields of data, gradient status pills, "create your first" empty state with five paragraphs of copy.

### Settings / configuration

**Reference**: Linear settings, Vercel project settings, Atlassian admin

Anatomy:
- Left nav: 220-280px, sections grouped (account, workspace, integrations).
- Form layout: single column, max-width 640-720px. Labels above fields.
- Save behavior: sticky save bar at bottom of viewport, OR auto-save with subtle confirmation.
- Section headers: H2 size, paired with one-line description.
- Dangerous actions: bottom of page, in red-bordered section, with confirmation dialog requiring typed-name.

Common slop: 2-column forms (hard to scan), modal-per-setting, save buttons inline per field.

### Onboarding

**Reference**: Linear, Vercel, Notion onboarding

Anatomy:
- 3-5 steps maximum. Progress indicator at top.
- One question per step, not a wall of fields.
- Skippable wherever possible (with revisit later).
- Final step: dispatches user into the app, not into another configuration screen.

Common slop: 8-step "create everything before you can start" flows, modal popups during onboarding.

### Detail view

**Reference**: Linear issue, GitHub PR, Stripe customer detail

Anatomy:
- Title + status row at top, full-width.
- Two-column or single-column body. Sidebar (right, 280-320px) for metadata.
- Activity / history below the fold.
- Primary action at top-right; destructive action in a menu.

### Form

**Reference**: Stripe payment, Vercel deploy config

Anatomy:
- Single column. Labels above fields. Help text below fields.
- Inline validation (after blur, not while typing).
- Required-field indicator: asterisk OR omit "optional" tag — pick one.
- Submit: single button, full-width on mobile, right-aligned on desktop.

### Empty state

**Reference**: Linear empty inbox, Notion empty page

Anatomy:
- Single sentence describing what goes here.
- Single primary CTA to create the first.
- Optional secondary link to docs / explanation.
- No illustration unless brand has earned visual identity.

## Banned references

Do NOT cite as good references:
- Bootstrap default theme (visually dated, dense)
- Material Design 2 (superseded — use M3)
- "Glassmorphism" tutorials (genre, not a design system)
- AI-generated UI showcases without provenance
