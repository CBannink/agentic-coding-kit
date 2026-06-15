---
name: redesign
description: "Use when the user asks to redesign, greenfield UI, multi-component visual refresh, or fresh look."
---

# /redesign

Use design specialists for visual judgment, then keep code completion on the
lean engineering loop.

Lock direction, capture current screens when available, use `ux-driver` and
`ui-driver` when design judgment is required, implement, run fresh build/test
and visual checks, then spawn `code-quality-reviewer`.

Spawn `security-reviewer` only for trust-boundary changes: auth/authz, secrets,
crypto, permissions, untrusted input, external HTTP, DB writes, filesystem
paths, command execution, payments, or sensitive data exposure.

Repair BLOCKING findings and rerun verification + review, max 3 repair cycles.

Do not spawn legacy reviewer/verifier agents as normal redesign gates. Do not
run writeback, reflection, or memory maintenance gates.
