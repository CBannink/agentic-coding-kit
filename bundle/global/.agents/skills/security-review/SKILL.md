---
name: security-review
description: Adversarial security audit. Fans out one agent per attack class (injection, authz, secrets, supply chain, IDOR, business logic) for parallel coverage. Includes false-positive verification pass and findings synthesis. Use only with authorization context — own code, internal repo, or explicit pentest brief.
---

# Security Review Skill

Adversarial audit using parallel attack-class agents. Independent attack
classes = clean swarm decomposition.

## Authorization gate

Before spawning anything, confirm one of:
- own code / repo (user is the author or contributor)
- internal company repo
- explicit pentest brief (CTF, authorized engagement, security research)

If none of the above apply, refuse and ask for context. The kit will not
generate offensive content for unauthorized targets.

## Steps

### 1. Confirm context

State the authorization basis explicitly in the run packet:

```powershell
pwsh ~/.agents/tools/run-packet.ps1 -SessionId $SessionId -AddNote "authz:<basis>|<details>"
```

### 2. Fan out — one agent per attack class

Default attack classes (configurable):
- **injection** — SQL, command, prompt, NoSQL, LDAP, XPath, header
- **authn-authz** — broken auth, session fixation, missing checks, privilege
  escalation, JWT issues
- **secrets** — hardcoded creds, exposed env, leaked keys, log scrubbing
- **supply-chain** — vulnerable deps, lockfile drift, typosquats, compromised
  packages, build script abuse
- **data-exposure** — IDOR, path traversal, SSRF, info disclosure, error leaks
- **business-logic** — race conditions, replay, idempotency, multi-step flow
  abuse, state confusion

Each agent receives:
- a narrow attack-class brief
- repo paths most relevant to that class (from a routing pass)
- output schema: `{severity, location, evidence, repro, recommendation}`

### 3. False-positive verification

Run a second pass over each finding. The verifier checks:
- can the finding be triggered with concrete inputs / state?
- is the trust boundary actually crossed, or is it intra-trust?
- is the recommendation aligned with the finding (not boilerplate)?

Findings that fail verification are dropped or downgraded with a note.

### 4. Synthesize

The synthesizer agent reads all verified findings and produces:
- deduplicated list (one finding per real issue, even if multiple agents found it)
- severity-ranked list
- explicit conflicts (e.g., one agent says X is exploitable, another says it's mitigated)
- a triage section for the user (must-fix / should-fix / nice-to-fix)

### 5. Write findings — to a session-private handoff, not memory.md

Security findings are sensitive. They go to:
`${AGENTS_SESSION_ROOT}/{session_id}/handoffs.md`

NOT to `.codex/context/memory.md` or `.wiki/features.md`. Sharing tag in
`handoffs.md` should NOT include sensitive details — only "security review
completed, see private handoff at <path>".

### 6. Write evidence

```powershell
pwsh ~/.agents/tools/workflow-evidence.ps1 -SessionId $SessionId -Tier SWARM -TierReason "security-review fan-out" -AddNote "security:classes=<list>|findings=<count>|verified=<count>"
```

## Anti-patterns

- **No authorization gate** — refuse, don't proceed
- **Skipping false-positive pass** — security swarms are noisy by design;
  unverified findings burn user trust
- **Writing findings to durable memory** — sensitive data should stay
  session-private until triaged
- **Generic recommendations** — "use prepared statements" is not a
  recommendation; "in `db/users.ts:42` replace the template literal with
  parameterized binding" is
