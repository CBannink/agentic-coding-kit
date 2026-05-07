# /redesign

Read and follow `__SKILL_ROOT__/redesign/SKILL.md` exactly.

__HOST_NAME__ adapter note:

1. This command is a workflow entrypoint, not a general chat shortcut.
2. Use the installed design and screenshot agents when the redesign skill
   delegates capture, structure critique, or visual critique.
3. Keep targeted UI fixes in `/build`; use `/redesign` for true multi-component
   visual work or swarm-safe fan-out.

Greenfield UI work or multi-component visual redesign. Swarm-eligible.

You must:
1. confirm scope is fan-out-able (independent components / screens, no shared state surgery)
2. read `.wiki/features.md` and any existing design system before planning
3. use `playwright-explorer` to capture current-state screenshots
4. spawn one `design-driver` agent per component or screen (parallel)
5. synthesize results into a single design system update
6. verify visually with before/after screenshots before claiming completion

If scope is targeted (one feature, tight coupling), drop back to sequential
`/build` instead -- swarms add coordination cost without quality gain on focused work.
