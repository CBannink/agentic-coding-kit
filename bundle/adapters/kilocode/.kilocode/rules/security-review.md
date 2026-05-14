# /security-review — Kilo Code custom mode (swarm-eligible)

Adversarial security audit. Read
`~/.agents/skills/security-review/SKILL.md` for the full template.

Authorization gate FIRST: confirm own code / internal repo / explicit
pentest brief. If none, refuse.

Lifecycle:
1. Fan out one agent per attack class (injection, authn-authz, secrets,
   supply-chain, data-exposure, business-logic).
2. False-positive verification pass over all findings.
3. Synthesize deduplicated, severity-ranked report.
4. Write findings to session-private handoff. NEVER to memory.md.
