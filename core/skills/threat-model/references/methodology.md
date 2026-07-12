# Threat-model methodology

## Establish the model

1. Bound the requested system and explicitly exclude unrelated surfaces.
2. Identify valuable assets and actors, including trusted operators and
   compromised or malicious users, services, and dependencies.
3. Trace data and control flows from current source and configuration.
4. Mark trust boundaries, privilege changes, persistence, external calls, and
   process boundaries.
5. Record existing preventative, detective, and recovery controls.

## Discover concrete threats

Apply only relevant lenses:

- identity spoofing, session abuse, and authentication bypass;
- tampering, injection, and unsafe deserialization;
- repudiation, missing auditability, and ambiguous ownership;
- sensitive-data disclosure and cross-tenant leakage;
- denial of service, amplification, resource exhaustion, and retry storms;
- privilege escalation and authorization bypass;
- filesystem, command, network, SSRF, IPC, tunnel, webhook, and supply-chain
  boundaries;
- payment, cryptographic, secret, and credential misuse;
- AI prompt injection, tool misuse, data poisoning, and sensitive output when
  the system actually contains AI surfaces.

Express each threat as an attack path with prerequisites and impact. Do not
list theoretical categories without a repository-specific path.

## Prioritize

Rank `CRITICAL`, `HIGH`, `MEDIUM`, or `LOW` from credible exploitability and
impact. State confidence separately. Prefer the minimum mitigation that breaks
the attack path and name executable or inspectable verification.
