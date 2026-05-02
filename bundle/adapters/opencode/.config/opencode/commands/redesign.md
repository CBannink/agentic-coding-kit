# /redesign

Greenfield UI work or multi-component visual redesign. Swarm-eligible.

You must:
1. confirm scope is fan-out-able (independent components / screens, no shared state surgery)
2. read `.wiki/features.md` and any existing design system before planning
3. use `playwright-explorer` to capture current-state screenshots
4. spawn one `design-driver` agent per component or screen (parallel)
5. synthesize results into a single design system update
6. verify visually with before/after screenshots before claiming completion

If scope is targeted (one feature, tight coupling), drop back to sequential
`/build` instead — swarms add coordination cost without quality gain on focused work.
