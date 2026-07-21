---
name: build
description: >-
  Implement repository features, fixes, refactors, migrations, configuration,
  UI, API, data, or code-linked documentation with proportionate proof.
---

# Build

Use the primary's shared orchestration, preservation, handoff, evidence,
repair, and completion policy. Infer affected behavior, ownership, callers,
compatibility, and assurance needs. Select the smallest reliable playbook:

- `INLINE`: inspect, implement, and verify directly. Keep a one-sentence active
  note naming the requested outcome and sufficient proof.
- `STANDARD`: use a light contract: outcome, relevant criterion IDs, preserve,
  implementation context, proof, and open facts. Add targeted discovery, one
  coherent Coder assignment, or one independent gate only when valuable.
- `DEEP`: maintain the full versioned Build Contract below; use focused
  discovery as needed, one coherent Coder, cheap checks, normally independent
  review, and only triggered hardening or specialists.

Playbooks are adaptive, not mandatory pipelines. Before editing, inspect live
instructions, Git state, relevant source/diffs, and unrelated changes. Verify
ownership and generated boundaries. Implement the smallest coherent delta.

For a clear defect, capture a red-capable symptom before repair when practical.
Trace affected public behavior and callers far enough to avoid local fixes that
break compatibility. Keep configuration, migration, error, and rollback effects
inside the contract when they are material. Edit canonical sources and use the
repository renderer for generated outputs.

Static inspection can establish non-behavioral work. Behavioral work requires
executable behavior evidence; type, lint, or build alone is insufficient unless
compilation or artifact generation is the requested behavior. If execution is
infeasible, record why and the remaining risk. Tests are conditional durable
evidence, not a required stage. A Test
Engineer is useful only for a specific independent gap.

Full `DEEP` contract:

```markdown
# Build Contract rN
## Request and outcome
## Verbatim user requirements (U1...)
## Derived proof/acceptance criteria (D1...; revisable, never broader than user intent)
## Current behavior and evidence
## Preserve and non-goals
## Relevant implementation context
## Proof plan
### Useful tests, if any
### Fast and final executable checks
### Independent or visual evidence, if triggered
## Assumptions and open facts
```

Load only what the change needs:

- [profiles.md](references/profiles.md) for assurance focus.
- [testing.md](references/testing.md) for test selection or hardening.
- [verification.md](references/verification.md) for evidence selection.
- [failures.md](references/failures.md) for failure classification.
- [handoffs.md](references/handoffs.md) for assignments and returns.
- [context-efficiency.md](references/context-efficiency.md) only for broad,
  long-running, or multi-agent work.
- [skill-authoring.md](references/skill-authoring.md) only when editing skills,
  agents, prompts, or their catalog metadata.

After the last relevant edit, run focused and repository-required checks. A
Coder reports `CONTRACT_GAP` rather than silently widening invalidated scope.
