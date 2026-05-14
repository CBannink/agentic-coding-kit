---
name: gstack-review
description: >
  Use when you want the sharper gstack-style specialist and adversarial review posture
  without adopting the full Claude-specific gstack runtime. Gives high signal-to-noise
  specialist decomposition, adversarial challenge, and production-risk framing.
  Requires premium reasoning model — always run with a premium reasoning model.
---

# Gstack Review

Apply gstack review discipline as a posture and pattern layer.
Do not import gstack telemetry, update checks, `~/.claude/skills/...` shell plumbing, or host-specific routing.

## Source Note

> **This wrapper is the authoritative operational reference.**
> The baked-in posture below is complete and self-contained — follow it directly.
>
> The raw vendored plugin at `~/.agents/workflows/plugins/gstack/review/SKILL.md`
> contains unresolved template/placeholder sections outside its preamble.
> **Do NOT load that file for operational execution.**
> It may be read for conceptual/background reference only; any template-style blocks
> in it must be ignored at runtime.

---

## Core Posture

**Specialist decomposition** — assign each concern to the most qualified reviewer, never conflate:
- security concerns → security-reviewer only
- performance concerns → performance-reviewer only
- API/contract concerns → api-reviewer only
- test gaps → testing-reviewer only

**Adversarial challenge** — after structured review, attack from a different angle:
- What would go wrong in production?
- What nasty edge case does the structured pass miss?
- What regression could this silently introduce?
- What happens under load, with bad input, or during partial failure?

**False-positive filtering** — read actual code before reporting:
- Never report based on assumptions about what the code does
- Open the file; read the actual implementation
- Downgrade findings that turn out to be handled correctly
- Only report what is concretely wrong

**Production-risk framing** — every High/Critical finding needs:
- The concrete real-world failure scenario
- Who is affected and how
- Whether there is a rollback or recovery path

## When to Use

- Code changes touching security, auth, or trust boundaries
- API contract changes where callers are not in the diff
- High-stakes refactors where silent regressions are possible
- Any review where the standard pass feels like it might miss something

## Workflow

1. Run a standard structured review first (software, security, api, testing).
2. Run a second adversarial pass asking: "What did the structured pass miss?"
3. Run the false-positive filter: read actual code for every finding before reporting.
4. Report only concrete, evidenced findings ordered by severity.
5. For each High/Critical: state the real-world failure mode explicitly.

## Source

Conceptual reference only — **not for operational use at runtime**:
- `~/.agents/workflows/plugins/gstack/review/SKILL.md` (raw vendored; contains unresolved template sections — ignore any runtime/operational blocks)
