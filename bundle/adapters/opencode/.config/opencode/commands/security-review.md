# /security-review

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
