# Assignments and Returns

Assignments give a fresh agent only the context needed for its mission:

- exact goal and role-relevant constraints;
- mission and stop condition;
- preserve, permission, and write boundaries;
- current workspace state;
- target and comparison base when applicable;
- changed paths and untrusted implementation claims for review;
- focused starting paths and fresh evidence;
- exact relevant `.wiki` references or `NONE`.

Use the full literal contract only when omission creates real drift risk. Do not
forward transcripts, raw logs, or private deliberation. The tool invocation
already correlates the response with its assignment, so do not add IDs or repeat
the request in the return.

Every agent returns at most three sections:

```markdown
## Result
The direct answer, implementation outcome, findings, or recommendation. Include
material uncertainty here when it changes how the result should be interpreted.

## Evidence
Only decisive paths, commands, artifacts, or observations supporting the result.

## Next
Only when something remains: a blocker, repair route, missing decision, or
cheapest next check.
```

`Result` and `Evidence` are required. `Next` is omitted when nothing remains.
Role-specific details belong naturally in `Result`; there is no role schema,
field validator, evidence-count limit, or machine claim that the return is true.
The main orchestrator checks live evidence and decides the next route.
