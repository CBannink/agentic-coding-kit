# Example: a real `/build` session, end-to-end

Concrete walkthrough of what happens when you run `/build add JWT auth flow` in OpenCode (or Claude Code) with the kit installed device-wide. Everything below is what the harness actually does, not what it theoretically could do.

## Setup (one time)

```bash
# Install the kit globally + adapters for all CLIs you might use
pwsh ./scripts/install.ps1 -DeviceWide all

# Verify
pwsh ./scripts/doctor.ps1
# Expected: 10+ checks, mostly PASS

# Open OpenCode in your project
cd ~/my-side-project
opencode
```

## In the OpenCode REPL

### Step 1 — You type the task

```
> /build add JWT login + token refresh
```

### Step 2 — Pre-session fires (automatic via OpenCode plugin)

```
╔══════════════════════════════════════════════╗
║  AGENT SESSION HARNESS -- pre-session         ║
╚══════════════════════════════════════════════╝

Running scope classifier...
  Scope:  CRITICAL -- Touches guarded/schema/auth file: src/auth/login.ts (matched pattern: auth)
  Tier rec: FULL -- CRITICAL scope always runs FULL
  (Orchestrator may override UPWARD only -- never downward)

Initializing session state...
  ✅ State initialized

Scanning session handoff index...
  Found 1 prior session(s) in index

Scanning global cross-repo INDEX.md...
  Found 1 cross-repo match(es) in global index

Reading recent history.md...
  Got 3 recent commit(s)

  Wiki: .wiki/features.md exists
```

A brief block is generated and shown to the agent. Notable fields:

```
- SCOPE: CRITICAL (Touches guarded/schema/auth file: src/auth/login.ts)
- TIER_REC: FULL
- WIKI: yes (.wiki/features.md exists -- read before explore phase)
- BUILD_BRIEF: none
- STATE_FILE: ~/.agents/session-state/2026-05-02--104500/state.json

## Cross-Repo Matches (semantically related work in OTHER repos)
| 2026-04-15 | other-repo | /build | implement-jwt-validation | jwt,auth |
```

### Step 3 — Agent reads the brief, follows the build skill

The agent reads `~/.agents/skills/build/SKILL.md` for the workflow. For CRITICAL scope at FULL tier, that includes:

- Phase 0: explore (read referenced files, including the cross-repo handoff for prior JWT work)
- Phase 1: plan (read `.wiki/features.md`, present plan)
- Phase 2-6: build loop (implement → review → verify → fix, max 5 iterations)

As it spawns subagents, it registers them with the cap enforced:

```bash
pwsh ~/.agents/tools/state-gate.ps1 -SessionId 2026-05-02--104500 -AddAgent "implementer" -EnforceAgentCap
# ✅ Agent 'implementer' registered (1/12)
```

### Step 4 — Test loop fires for verification

When ready to verify:

```bash
pwsh ~/.agents/tools/test-loop.ps1 -SessionId 2026-05-02--104500 -Command "npm test"
```

The runner:
- Executes `npm test` via .NET Process API (not Start-Job — proper exit code capture)
- Captures stdout+stderr to `~/.agents/session-state/<id>/test-captures/iter-001.log`
- Computes a normalized failure signature (strips line numbers, paths, timestamps)
- Writes JSON record to `test-loop-runs.jsonl`
- On pass: marks `verification_evidence` gate, adds command to workflow-evidence
- On fail: returns the tail formatted for diagnosis
- On 3-in-a-row same signature: status="stuck", exit code 3, escalation message

### Step 5 — Edit linting (refuses bad changes)

When the agent wants to apply a code edit:

```bash
pwsh ~/.agents/tools/edit-with-lint.ps1 \
    -Path src/auth/login.ts \
    -Find "function login()" \
    -Replace "function login(email: string, password: string)"
```

What happens:
- Reads file, counts occurrences (refuses 0 matches OR >1 matches without `-All`)
- Writes change to temp file
- Auto-detects `.ts` linter → `node --check`
- Runs lint on temp file
- If pass: atomic move temp → original
- If fail: discards temp, returns lint output for the agent to fix
- Returns JSON: `{path, applied, reverted, lint_status, lint_output, before_sha, after_sha}`

If `node` isn't installed, lint is gracefully skipped — edit applies anyway.

### Step 6 — Mark gates as you go

```bash
pwsh ~/.agents/tools/state-gate.ps1 -SessionId 2026-05-02--104500 -Mark "context_loaded"
pwsh ~/.agents/tools/state-gate.ps1 -SessionId 2026-05-02--104500 -Mark "implementation_done"
# verification_evidence gets marked automatically by test-loop on pass
```

### Step 7 — Session ends, post-session fires (automatic)

```
╔══════════════════════════════════════════════╗
║  AGENT SESSION HARNESS -- post-session        ║
╚══════════════════════════════════════════════╝

Gate Status (scope: CRITICAL)
  ✅ scope_classified
  ✅ context_loaded
  ✅ rubber_duck_consulted
  ✅ consequence_traced
  ✅ implementation_done
  ✅ verification_evidence
  ⬜ false_positive_verified (optional for CRITICAL but flagged)

  Agents run: explorer, implementer, security-reviewer, false-positive-verifier

✅ Private handoff written: ~/.agents/session-state/2026-05-02--104500/handoffs.md
✅ Handoff registered in .codex/context/memory.md
  Appended to global INDEX.md
✅ Shared handoffs index updated
✅ Machine-readable handoff index updated

Auto-consolidating reflections...
  no consolidation needed

Compressing memory...
  no consolidation needed

╔══════════════════════════════════════════════╗
║  Session registered. Harness complete. ✅    ║
╚══════════════════════════════════════════════╝
```

If a recurring kit-level pattern was detected this session, you'd see:

```
╔══════════════════════════════════════════════════════════════════╗
║  ⚠ NEW HARNESS PROPOSAL(S): 1  ─ recurring failure pattern(s)    ║
╚══════════════════════════════════════════════════════════════════╝
  • [verification] seen 5x  Verification command appears to be gaming the gate

  Review (does NOT auto-apply):
    pwsh ~/.agents/tools/harness-review.ps1
    pwsh ~/.agents/tools/harness-review.ps1 -Show <id>
    pwsh ~/.agents/tools/harness-review.ps1 -ProposalId <id> -Action accept|reject|defer -Note '...'
```

This banner only appears when 5+ occurrences AND 3+ within 30 days AND matches kit vocabulary. Most sessions stay silent.

## What got created on disk

After the session above:

```
~/.agents/session-state/2026-05-02--104500/
├── state.json              # gate state, agent count
├── session-meta.json       # task, mode, started_at
├── run-packet.json         # compact session contract
├── workflow-evidence.json  # tier, scope, agents, verification commands
├── handoffs.md             # human-readable session handoff
├── hook-events.jsonl       # session-start, subagent-stop events
├── test-captures/          # raw test output per iteration
│   ├── iter-001.log
│   └── iter-002.log
└── test-loop-runs.jsonl    # structured test results

~/.agents/session-state/INDEX.md          # appended one row
~/my-side-project/.codex/context/memory.md # handoff index updated
```

Next time you start a session in any repo, pre-session reads INDEX.md and surfaces this session as a cross-repo match if the keywords overlap.

## What if things go wrong

**Test loop gets stuck (same failure 3x)**:
```
{
  "iteration": 5,
  "status": "stuck",
  "exit_code": 7,
  "escalation": "Same failure signature has occurred 3 times in a row. Stop doubling down -- try a different approach."
}
```
Exit code 3 — caller (agent) sees the escalation and changes strategy.

**Reflection gate trips at session end**:
```
🔁 SELF-IMPROVEMENT GATE: 6 unaddressed reflections (>=5)
   Run /reflect before opening another session.
```
Next pre-session in any repo will surface this. In NonInteractive mode (hooks), exits 2 to signal the host.

**Edit linter rejects your change**:
```json
{
  "applied": false,
  "reverted": true,
  "lint_status": "fail",
  "lint_output": "src/auth/login.ts:5:12: SyntaxError: Unexpected token ')'"
}
```
Your `src/auth/login.ts` is unchanged. Agent reads the lint output and tries again.

## What you do as the user

- Type `/build <task>` in the REPL
- Read what the agent shows you, approve plans before they ship
- Watch for the yellow banner at session end (rare, only fires on real recurring patterns)
- Run `pwsh ~/.agents/tools/harness-review.ps1` if a banner appears
- Accept/reject proposals; implement accepted ones manually

That's the whole loop. The harness makes most decisions mechanically; you stay in the loop only for judgment calls.

## What this kit does NOT do

- Auto-modify its own scripts (proposals are written, never applied)
- Auto-apply workflow changes that need judgment (those go through `/reflect`)
- Skip verification (test-loop refuses to mark the gate without running the command)
- Hide failures (every objective failure becomes a reflection entry, eventually a proposal)

That's the discipline. Now go run a real session.
