# Workflow Evidence Protocol

Canonical session-proof capture for all workflow modes.

## Purpose

The workflow can only be judged fairly if it leaves structured evidence of:
- which mode ran
- which tier was chosen
- why agents were spawned or skipped
- which repo context was actually used
- which verification commands were run
- why memory/history/wiki writes were skipped or performed

Store this evidence in:

`${AGENTS_SESSION_ROOT}/{session_id}/workflow-evidence.json` (default `.kit/session-state/{session_id}/workflow-evidence.json` in a bootstrapped repo)

using:

`pwsh ~/.agents/tools/workflow-evidence.ps1`

## Minimum fields

Every `/build`, `/review`, `/analyze`, and `/investigate` session should capture:

- `mode_sequence`
- `tier`
- `tier_reason`
- `scope`
- `scope_reason`
- `repo_context_used`
- `build_brief_used`
- `agents_spawned`
- `agents_skipped`
- `mode_decisions`
- `review_checks`
- `verification_commands`
- `write_decisions.memory`
- `write_decisions.history`
- `write_decisions.wiki`

If something is intentionally skipped, record the skip explicitly. "No-op with reason" is evidence. Silence is ambiguity.

## Event examples

```powershell
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId "{id}" -Mode "build" -Scope "SHARED" -ScopeReason "touches 3 files across src+test"
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId "{id}" -Tier "TARGETED" -TierReason "3-file scoped fix; wiki already maps feature"
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId "{id}" -AddRepoContext ".kit/context/memory.md"
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId "{id}" -BuildBrief "no same-day brief found"
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId "{id}" -AddAgent "spec-reviewer|scope verification on changed diff"
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId "{id}" -AddSkippedAgent "implementer|mechanical two-file fix handled inline"
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId "{id}" -AddModeDecision "/investigate skipped|failing test + code read already confirmed the defect"
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId "{id}" -AddReviewCheck "INLINE review|confirmed minimal diff, no untouched behavior drift, verification claims matched output"
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId "{id}" -AddVerification "npm test"
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId "{id}" -MemoryDecision "skipped: no new durable repo fact"
```

## Output discipline

Before final completion, include a compact **Workflow Evidence** block in the response or handoff summary using the same fields. Keep it short, but make the decisions auditable.
