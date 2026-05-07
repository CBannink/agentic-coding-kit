# /refactor

Read and follow `__SKILL_ROOT__/refactor/SKILL.md` exactly.

__HOST_NAME__ adapter note:

1. This command is a workflow entrypoint, not a general chat shortcut.
2. Use the installed explorer / reviewer agents when the refactor skill says to
   map structure, trace consequences, or pressure-test architectural changes.
3. Preserve behavior; do not treat `/refactor` as permission to redesign inline
   in the main session without the workflow's consequence and review passes.

Principle-driven restructuring with consequence tracing.

You must:
1. classify scope first (`scope-classifier.ps1`); CRITICAL scope is rarely a
   refactor -- challenge whether this is the right framing
2. trace consequences (`consequence` skill) before any edit
3. preserve behavior -- refactor changes structure, not behavior
4. verify with the existing test suite; if no tests, write characterization
   tests first
5. for multi-module refactors with independent files, swarm is allowed
   (parallel-safe verb + fan-out-able scope); otherwise sequential
