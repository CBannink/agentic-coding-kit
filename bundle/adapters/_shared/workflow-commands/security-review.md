---
description: User-typed /security-review entry point. Run an authorized security audit on __HOST_NAME__.
---

# /security-review

You are the main Claude Code / OpenCode session. This workflow is report-only
unless the user separately asks to fix findings.

## Authorization Gate

Confirm the target is the user's code, repo, or authorized engagement. If
unclear, stop and ask before reviewing.

## Review Loop

1. Scope the audit: whole repo, specific diff, or specific concern.
2. Spawn `security-reviewer` for the relevant trust-boundary classes:
   auth/authz, secrets, crypto, permissions, untrusted input, external HTTP, DB
   writes, filesystem paths, command execution, payments, or sensitive data
   exposure.
3. Use `code-quality-reviewer` only when the user also asks for general code
   quality or when a security finding depends on ordinary correctness/test
   quality.
4. Manually false-positive-check CRITICAL/HIGH findings by reading the cited
   code and nearby mitigations.
5. Return one consolidated security report with severity, file:line, impact, and
   remediation.

Do not run writeback, reflection, memory maintenance, or verifier gates.

## Not Default

Do not spawn legacy reviewer or verifier agents as part of normal
`/security-review`.
