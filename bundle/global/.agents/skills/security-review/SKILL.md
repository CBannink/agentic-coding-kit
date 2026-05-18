---
name: security-review
description: Use when the user asks to security audit, pentest, vulnerability scan, or OWASP review. Runs authorization gate, parallel attack-class fan-out, false-positive verification, severity-ranked report.
---

# /security-review

Adversarial audit. Do NOT fix vulnerabilities — report only.

## Phase 0 — Authorization gate

Confirm with the user: is this YOUR code / YOUR repo / an authorized pentest? If unclear, STOP and ask. Do NOT run on third-party code without explicit permission.

## Phase 1 — Scope

- **Whole repo**: fan out across all attack classes in parallel.
- **Specific diff**: focused review of changed files.
- **Specific concern**: single-class deep dive.

## Phase 2 — Parallel attack-class fan-out

Spawn `security-reviewer` instances in parallel, each scoped to ONE attack class:

| Class | Focus |
|---|---|
| Injection | SQL, command, path traversal, template, NoSQL, prompt injection |
| AuthN/AuthZ | Broken auth, missing checks, IDOR, privilege escalation |
| Secrets | Hardcoded keys, leaked tokens, weak crypto |
| Supply chain | Dependency vulnerabilities, lockfile drift, unverified installs |
| Business logic | Race conditions, TOCTOU, state machine bugs, missing rate limits |
| Data exposure | PII in logs, missing encryption, overpermissive responses |

Cap parallel spawns at 4-6 depending on host constraints. Each returns findings with file:line, severity (CRITICAL/HIGH/MEDIUM/LOW), and theoretical or proven classification.

## Phase 3 — False-positive verification

For every CRITICAL and HIGH finding: read the file:line yourself. Check for mitigations (sanitizers, framework auto-escaping, auth middleware, WAF rules). Downgrade verified-false to NIT or remove entirely.

## Phase 4 — Consolidated report

Structure the report:
- **CRITICAL**: must-fix before merge/deploy
- **HIGH**: should-fix this sprint
- **MEDIUM/LOW**: backlog
- Each finding: file:line + concrete remediation
- Authorization disclaimer (reviewed YOUR code per Phase 0)

## What you DO NOT do

- Do NOT fix vulnerabilities. Report only.
- Do NOT skip the authorization gate.
- Do NOT report theoretical-only findings at CRITICAL/HIGH without checking mitigations first.
