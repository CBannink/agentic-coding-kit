---
name: gstack-office-hours
description: >
  Use for product-wedge, user-problem, and status-quo-replacement analysis.
  Applies gstack office-hours framing: is this the right problem? is this the wedge?
  what is the user's actual pain? what does "replacing the status quo" look like?
  Requires deep reasoning — always run with a premium reasoning model.
---

# Gstack Office Hours

Apply gstack office-hours as a product and wedge analysis framework.
Do not import Claude-specific runtime instructions.

## Dynamic Source Loading

**Read this file first**, then apply its full instructional content (skip the `## Preamble` bash block):

```
~/.agents/workflows/plugins/gstack/office-hours/SKILL.md
```

The baked-in questions below are the distilled version. The source file has the full Startup vs Builder mode branching, forcing question depth, and design-doc output format. If readable, prefer the source file.

---

## Core Questions

When any product decision, feature design, or "what should we build" question arises, apply these:

### 1. What is the user's actual problem?
- Not what the user asked for — what pain are they experiencing?
- What does their current workflow look like without this feature?
- What is the most frustrating part of their current situation?

### 2. What is the status quo being replaced?
- What do users do today to solve this problem?
- Is the status quo a manual process? A different tool? Doing nothing?
- Why has the status quo persisted — what keeps users from switching?

### 3. What is the wedge?
- The wedge is the smallest thing that makes the alternative undeniably better in one dimension.
- What single capability, if delivered well, would make the user say "this is better"?
- Is the proposed feature the wedge, or is it building infrastructure around the wedge?

### 4. Is this the right scope?
- Are we building the wedge, or are we building around it hoping the wedge emerges?
- What would we cut to focus entirely on the wedge?
- What is the minimum viable version that proves the wedge works?

### 5. What does success look like?
- How does the user know this worked?
- What behavior change in the user's workflow proves this was the right bet?

## When to Use

- Product direction decisions ("should we add X or Y?")
- Feature scoping ("what is the most important thing to build next?")
- Architecture selection where user value is a deciding factor
- Any time a build request feels like it might be solving the wrong problem

## Source

Reference layer only (no runtime import):
- `~/.agents/workflows/plugins/gstack/office-hours/SKILL.md`
