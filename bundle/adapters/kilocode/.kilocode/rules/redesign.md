# /redesign — Kilo Code custom mode (swarm-eligible)

Greenfield UI / multi-component redesign. Read
`~/.agents/skills/redesign/SKILL.md` for the full template.

Lifecycle:
1. Capture before-state with `playwright-runner.ps1`.
2. Fan out one `design-driver` agent per screen / component.
3. Capture after-state.
4. Visual diff with `visual-diff.ps1`.
5. Synthesize per-component changes into a coherent design system.

Eligibility check first: `swarm-classifier.ps1` must return
`mode: swarm-fanout`. If task is targeted polish, drop back to /build.
