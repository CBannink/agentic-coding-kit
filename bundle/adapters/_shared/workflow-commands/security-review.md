---
description: User-typed /security-review entry point. Run the kit's phased pipeline for this workflow on __HOST_NAME__. Main session orchestrates; spawns workflow-explorer / workflow-implementer / specialist agents (code-quality-reviewer, security-reviewer, modularity-expert, final-verifier) via the Task tool per phase. Description-match also routes to the matching security-review-orchestrator subagent if loaded; both paths reach the same leaves.
---

# /security-review

You are the main Claude Code / OpenCode session. The user invoked /security-review because they want to security audit, pentest, vulnerability scan. You ARE the orchestrator — no wrapping subagent layer; you read this body and execute the phases yourself, using the **Task tool** to spawn leaf subagents (workflow-explorer, workflow-implementer, code-quality-reviewer, etc.) when phases call for it.

Adversarial security audit by attack class. You ARE the orchestrator.

## Authorization gate (READ FIRST)

Confirm with the user before proceeding:
- Is this YOUR code / YOUR repo / part of an authorized pentest engagement?
- If unclear, STOP and ask. Don't run security analysis on third-party code without explicit permission.

## Phase 1 — Scope

- Whole repo? → swarm fan-out across attack classes.
- Specific diff? → focused review of the diff.
- Specific concern (e.g., "is the auth flow safe")? → single-class deep dive.

## Phase 2 — Parallel attack-class fan-out

Spawn in parallel via simultaneous Task calls (max ~6):
- **Injection** — SQL, command, path traversal, template, NoSQL, prompt injection. Spawn `security-reviewer` scoped to injection.
- **AuthN/AuthZ** — broken auth, missing checks, IDOR, privilege escalation.
- **Secrets** — hardcoded keys, leaked tokens, weak crypto.
- **Supply chain** — dependency vulnerabilities, lockfile drift, unverified install scripts.
- **Business logic** — race conditions, TOCTOU, state machine bugs, missing rate limits.
- **Data exposure** — PII in logs, missing encryption at rest, overpermissive responses.

Each returns findings with file:line, severity (CRITICAL/HIGH/MEDIUM/LOW), and PoC OR "theoretical" tag.

## Phase 3 — False-positive verification

For every CRITICAL or HIGH finding: read cited file:line yourself, check for mitigations elsewhere (sanitizers, framework auto-escaping, auth middleware higher in stack). Downgrade verified-false to NIT or remove.

## Phase 4 — Synthesis

Return ONE consolidated security report:
- CRITICAL: must-fix before merge/deploy.
- HIGH: should-fix this sprint.
- MEDIUM/LOW: backlog.
- Each finding with file:line + concrete remediation.
- Authorization-context disclaimer (this was a review of YOUR code per Phase 0).

## What NOT to do

- Do NOT fix vulnerabilities. /security-review is report-only.
- Do NOT skip Phase 3 — security false-positives erode trust.
## Phase 5b — Mechanical writeback gate (run this, do not skip)

After verification passes, run the writeback gate via Bash:

```
pwsh ~/.agents/tools/verify-writeback.ps1 -SessionId "$CLAUDE_SESSION_ID"
```

Output ends with `OK writeback: ...` (proceed) or `WARN NO WRITEBACK -- ...`. If WARN: either update `.wiki/features.md` / `.kit/context/memory.md` and re-run, OR include the warning in your final response so the user sees the gap. Do NOT silently skip.

## Phase 5c — Reflect trigger (mechanical)

Check `~/.agents/context/reflections.md` length. If 5+ unaddressed entries: spawn the `reflect` skill via the Skill tool (or surface to user "5+ workflow reflections accumulated, recommend running /reflect"). Mechanical, not vibes.

## Simplification policy

For ISOLATED scope (Phase 0 classified) you may compress:
- Phase 1 (explorer): skip if codebase is small / already understood.
- Phase 3 (reviewers): code-quality-reviewer only (skip security + modularity unless triggers fire).
- Phase 4 (adversarial): SKIP entirely.

Min spawns for ISOLATED: 2 (workflow-implementer + final-verifier). Max for SHARED: 7. CRITICAL adds 1-2 more iterations on the fix-loop.