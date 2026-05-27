---
name: aesthetic-director
description: Use before UI generation to choose a visual direction and write DESIGN.md. Trigger for redesigns, fresh looks, or theme setup.
---

# Aesthetic Director

The skill that **picks an aesthetic direction before any code is written**, so
downstream design agents generate variations of one coherent look instead of
inventing a fresh AI-default on every prompt.

## Why this exists

The kit's `ux-driver`, `ui-driver`, `design-driver`, and `redesign` skills all
read `DESIGN.md` if it exists — but nothing in the kit *creates* one. The
default LLM frontend output is recognizable: Inter, purple gradient, rounded
cards, generic spacing. This skill replaces that default with an explicit,
named direction the rest of the pipeline can hold to.

Pattern lifted from Anthropic's official Frontend Aesthetics Cookbook
(https://platform.claude.com/cookbook/coding-prompting-for-frontend-aesthetics).
The cookbook approach: pick the aesthetic *before* generating, encode it as a
short directive block, then enforce it on every UI prompt. Five lines of text,
massive output difference.

---

## When to invoke

- `/redesign` Phase 0 when no `DESIGN.md` (or `design-system.md`) exists in the repo
- `/build` Phase 0 when frontend-detector flags greenfield UI work and no DESIGN.md exists
- Standalone when the user says "theme this", "fresh look", "make it look like X", "design system"

**Skip** when:
- DESIGN.md already exists and the user hasn't asked to redo it (read it, don't replace it)
- The change is single-component polish only (use `design-driver` directly)
- The repo has an upstream brand system the user must conform to (read it, don't override)

---

## Inputs

- repo root, optional `.wiki/features.md` (what the product does — informs aesthetic fit)
- the user's brief if any ("fintech", "developer tool", "luxury e-commerce", or a named direction)
- existing brand assets if any (logo, primary color, prior screenshots)

---

## Workflow

### 1. Check for prior DESIGN.md

```powershell
Test-Path DESIGN.md, design-system.md, docs/design-system.md, .wiki/design-system.md
```

If present → **stop, read it, return its summary**. Do not overwrite. The
caller (redesign / build) wanted a direction; one already exists.

### 2. Frame the product

Read `.wiki/features.md` if present — get one paragraph on what the product
does and who uses it. The aesthetic must serve the product, not fight it.
A B2B compliance dashboard should not be cyberpunk. A music NFT platform
probably should not be Swiss minimalism.

### 3. Propose 2-3 named directions

Pick from the named-aesthetic vocabulary below (or invent one — these are
just well-known anchors). For each, give:

- **One-line essence**
- **Type pairing** (display + body)
- **Palette starting points** (primary, neutral, accent — 3 colors max)
- **Density** (spacious / balanced / compact)
- **Motion** (none / subtle / cinematic)

Present 2-3 options to the user, never one. The user picks. Do not generate
code yet.

### 4. Lock the choice

Once the user picks, write `DESIGN.md` at repo root with:

```markdown
# Design System -- {AESTHETIC_NAME}

## Direction
{One paragraph on the aesthetic's essence and why it fits this product.}

## Typography
- **Display**: {font, weight, tracking}
- **Body**: {font, weight, line-height}
- **Mono**: {font for code/data}

## Palette
- **Primary**: {oklch or hex}
- **Background**: {oklch or hex}
- **Foreground**: {oklch or hex}
- **Accent**: {oklch or hex}
- **Border**: {oklch or hex}
(Prefer OKLCH over hex for perceptual uniformity. P3 wide-gamut colors render correctly on modern displays.)

## Density
{spacious | balanced | compact} -- {one-line rationale}

## Motion
{none | subtle | cinematic} -- {when motion is appropriate, what's banned}

## Banned defaults
- {explicit list of LLM defaults to avoid: e.g. "Inter font", "purple gradient backgrounds", "rounded-2xl cards", "shadow-sm everywhere"}

## References
- {1-3 reference sites or design systems that exemplify this direction}
```

### 5. Optionally append a CLAUDE.md theme block

If the project has a `CLAUDE.md`, offer to append a 5-10 line lock block:

```markdown
## Frontend Theme
<always_use_{aesthetic_slug}_theme>
Always design with {AESTHETIC_NAME} aesthetic:
- {3-5 directives lifted from DESIGN.md}
- Banned: {2-3 LLM defaults to never produce}
</always_use_{aesthetic_slug}_theme>
```

This binds every future Claude Code prompt in this repo to the locked
direction without re-explaining it. Ask before editing CLAUDE.md.

### 6. Hand back to the caller

Return: `{ design_md_path, aesthetic_name, claude_md_updated: bool }`. The
caller (`redesign`, `build`, or the user) takes it from there.

---

## Named aesthetic vocabulary

Use these as starting anchors. Mix and adapt. The named direction is just
shorthand — the locked DESIGN.md is what downstream agents actually read.

| # | Aesthetic | Think... | Good for |
|---|-----------|----------|----------|
| 1 | Swiss Minimalism | Helvetica, grids, white space, no decoration | enterprise, content sites, docs |
| 2 | Editorial | Serif headlines, magazine grid, pull quotes | publishing, long-form, premium content |
| 3 | Brutalism | System fonts, raw layout, visible borders, loud color | indie tools, anti-design, devtools |
| 4 | Glassmorphism | Frosted glass, blur, transparency | modern SaaS dashboards, fintech |
| 5 | Neumorphism | Soft shadows, extruded elements | calm tools, single-purpose utilities |
| 6 | Claymorphism | 3D clay blobs, soft shapes, friendly | consumer apps, kid/family products |
| 7 | Aurora Mesh Gradient | Flowing gradients, soft color | landing pages, AI products |
| 8 | Retro-Futuristic / Cyberpunk | Neon on dark, mono type, scanlines | gaming, web3, DJ tools |
| 9 | Dark OLED Luxury | True black bg, gold/cream accents, thin serif | luxury, premium subscriptions |
| 10 | Vibrant Maximalist | Color blocks, loud type, no white space | youth brands, music, social |
| 11 | Organic Biomorphic | Earth tones, rounded shapes, warm shadows | wellness, slow web, sustainability |
| 12 | Solarpunk | Greens/golds, optimistic, retro-futuristic | climate, regenerative tech |

These are starting points, not a closed set. Match the aesthetic to the
product's actual identity — never default to "modern SaaS" because it's safe.

---

## Output discipline

- **Never generate UI code in this skill.** Direction only. Code generation
  belongs to `redesign` / `build` / `design-driver`.
- **Always present 2-3 options, never one.** A single proposal feels
  prescriptive; options force the user to articulate why one fits.
- **Lock with OKLCH where possible**, not hex. Modern displays are P3 wide
  gamut; OKLCH gives better perceptual uniformity and works with the
  Tailwind v4 `@theme` block.
- **Banned-defaults list is mandatory.** Every DESIGN.md must explicitly
  enumerate the LLM defaults to avoid (Inter, purple gradient, rounded-2xl,
  generic shadows). Without this, downstream agents drift back to defaults.
- **One sentence on motion is enough.** Detailed motion specs go in a
  separate `MOTION-SPEC.md` if motion is heavy in the product.

---

## Relation to other kit skills

| Skill | What it does | This skill's relation |
|-------|--------------|------------------------|
| `redesign` | Multi-screen visual rebuild | Calls aesthetic-director if no DESIGN.md, then proceeds |
| `ux-driver` | Structural critique | Reads DESIGN.md to know what "looks right" means here |
| `ui-driver` | Visual polish critique | Reads DESIGN.md banned-defaults list to flag drift |
| `design-driver` | Solo INLINE polish | Reads DESIGN.md if present, otherwise uses generic taste |
| `build` (frontend phase) | Greenfield UI | Should invoke aesthetic-director Phase 0 if frontend-detector flags new UI |

This skill is **upstream** of all the design critics. It tells them what to
hold to.
