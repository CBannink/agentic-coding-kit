# /refactor

Principle-driven restructuring with consequence tracing.

You must:
1. classify scope first (`scope-classifier.ps1`); CRITICAL scope is rarely a
   refactor — challenge whether this is the right framing
2. trace consequences (`consequence` skill) before any edit
3. preserve behavior — refactor changes structure, not behavior
4. verify with the existing test suite; if no tests, write characterization
   tests first
5. for multi-module refactors with independent files, swarm is allowed
   (parallel-safe verb + fan-out-able scope); otherwise sequential
