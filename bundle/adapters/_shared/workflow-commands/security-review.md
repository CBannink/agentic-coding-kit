# /security-review

Read and follow `__SKILL_ROOT__/security-review/SKILL.md` exactly.

__HOST_NAME__ adapter note:

1. This command is a workflow entrypoint, not a general chat shortcut.
2. Use the installed specialists and swarm-safe fan-out when the security
   review skill says to split by attack class.
3. Keep the session in evidence mode: severity, proof, and false-positive
   filtering before final conclusions.

Adversarial security audit. Swarm-eligible.

You must:
1. confirm authorization context (own code, internal repo, or explicit pentest brief)
2. fan out one agent per attack class:
   - injection (SQL, command, prompt)
   - authn / authz / session
   - secrets / credentials
   - supply chain / deps
   - data exposure / IDOR / path traversal
   - business logic abuse
3. each agent produces findings with severity, evidence, repro steps
4. synthesize into a single report with deduplicated findings
5. run a false-positive verification pass before final report
6. write findings to a session-private handoff, not to memory.md

Swarm parallelism is appropriate here because attack classes are independent.
For incident response on a known vulnerability, use `/investigate` instead.
