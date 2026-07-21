---
name: threat-model
description: >-
  Threat-model a feature, system, or change through assets, trust boundaries,
  controls, and concrete attack paths without changing implementation.
---

# Threat Model

Remain read-only unless the user explicitly approves a report target path.
Threat-modeling does not authorize implementation; transition requested fixes
into the `build` skill.

Choose the smallest useful route:

- `FOCUSED` examines one feature, component, or changed trust boundary.
- `FULL` maps the requested system surface end to end.
- `INCREMENTAL` compares an existing threat model with the current diff.

Read only relevant architecture, API, auth, data, IPC, integration, and
engineering wiki sections, then verify them against current source. Use a
targeted `repo-scout` only when flows or ownership are unclear. Identify assets,
actors, data flows, trust boundaries, existing controls, and applicable threats.
Use the core `security-reviewer` for an independent challenge when material
security judgment remains. Every agent returns to the main orchestrator.

Return `COMPLETE`, `NEEDS_CONTEXT`, or `BLOCKED`. Include concrete evidence,
ranked threats, mitigations, verification, residual risk, assumptions, and
confidence. Missing evidence remains missing.

Load [methodology.md](references/methodology.md) for threat discovery and
prioritization, [modes.md](references/modes.md) for route-specific procedure,
and [report.md](references/report.md) for the output contract.
