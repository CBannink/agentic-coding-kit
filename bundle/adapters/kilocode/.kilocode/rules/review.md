# /review — Kilo Code custom mode

When the user invokes `/review` or asks for a code review / audit:

1. Read `~/.agents/skills/review/SKILL.md`.
2. Run hierarchical review: surface reviewers (software, security, api as
   appropriate) → interactions → synthesis → adversarial → false-positive
   verifier.
3. For small focused diffs with parallel-safe verb, use the parallel-reviewers
   mode (`swarm-review`) — sequential implementer + N concurrent reviewers.
4. Write findings to a session-private handoff, NOT memory.md.

Run `pwsh ~/.agents/tools/specialist-memory-resolver.ps1 -Role <role>`
before spawning each reviewer that may need repo-local context.
