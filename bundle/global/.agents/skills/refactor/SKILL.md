---
name: refactor
description: "Use when the user asks to refactor, restructure, clean up, consolidate, or apply DRY/SOLID while preserving behavior."
---

# /refactor

Name the refactor principle, map affected call sites when needed, implement,
run fresh verification, then use `code-quality-reviewer` to confirm behavior is
unchanged and structure improved.

Spawn `security-reviewer` only if the refactor touches auth/authz, secrets,
crypto, permissions, untrusted input, external HTTP, DB writes, filesystem
paths, command execution, payments, or sensitive data exposure.

Repair BLOCKING findings and rerun verification + review, max 3 repair cycles.

Do not spawn legacy reviewer/verifier agents in the default refactor loop. Do
not run writeback, reflection, or memory maintenance gates.
