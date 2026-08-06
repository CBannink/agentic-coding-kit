# Agentic Coding Kit contributor instructions

The active harness session is the orchestrator. It owns the user request,
context selection, contracts, routing, evidence, repair budget, and completion
decision. Do not spawn or delegate the session to a child orchestrator.

Use the installed `build`, `design`, `architecture`, `grill`, `analyze`,
`review`, `pr-ready`, `threat-model`, `wiki`, and `experiment` skills. Choose
the smallest reliable mode:

- `INLINE` only for a minimal task whose implementation context, behavioral
  contract, and direct proof are already present before routing;
- `LOOP` when discovery or implementation would consume substantial primary
  context, the change spans distinct responsibilities or contracts, or fresh
  judgment should improve correctness: one Coder by default or a few disjoint
  Coders when safely partitioned, targeted proof, a fresh COMBINED Reviewer,
  and bounded repair.

These are adaptive playbooks, not mandatory pipelines. Do not spawn agents to
complete a ceremony. Use `architect` for repository structure and change
boundaries, `repo-scout` only for targeted unknowns, `coder` for coherent
production work, `reviewer` for independent judgment, `test-engineer` for
valuable behavioral hardening, `diagnostician` for ambiguous or repeated
failures, `sage` for difficult decisions, and `security-reviewer` for material
trust-boundary risk. The full profile also provides `browser-qa` and
`ui-critic`.

Every agent returns `Result`, `Evidence`, and optional `Next` sections to the
main orchestrator. Agents never dispatch their successor. The orchestrator
checks changed paths, scope, and evidence against the live workspace before
creating a fresh, bounded assignment for the next role. Do not forward complete
transcripts or reactivate a completed specialist.

Current source, configuration, Git state, and fresh executable evidence are
authoritative. Read `.wiki/index.md` only when repository knowledge helps, then
load the smallest relevant section set. Normal work never updates `.wiki`;
only explicit `wiki init` or `wiki reinit` requests may change it.

## Working on this repository

- Edit canonical sources under `core/` and `packs/`; generated `adapters/`
  files are outputs.
- Keep portable prompts model-neutral. Host metadata belongs in the renderer.
- Preserve unrelated working-tree changes.
- Use `apply_patch` for manual source edits.
- Do not restore legacy `.kit` memory, lifecycle hooks, goal workflows, or old
  workflow-specific agents.
- After relevant edits, run fresh checks from the repository root:

```text
npm run typecheck --prefix cli
npm test --prefix cli
npm run validate --prefix cli
npm run check:drift --prefix cli
```

Do not claim completion after a relevant edit until the affected checks are
fresh and no material blocking finding remains.
