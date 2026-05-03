# Third-Party Attribution

This kit packages, references, or is inspired by patterns from upstream
projects. Their respective licenses apply to content sourced from those
projects. The MIT license in `LICENSE` covers original work in this repo.

## Upstream-derived content

Files under `bundle/global/.agents/workflows/plugins/` reference or
adapt material from:

- **GStack** ([garrytan/gstack](https://github.com/garrytan/gstack)) — engineering team
  simulation skills (`gstack/investigate`, `gstack/office-hours`,
  `gstack/plan-eng-review`, `gstack/qa`, `gstack/review` with specialists).
- **Superpowers** ([obra/superpowers](https://github.com/obra/superpowers)) — agent discipline
  patterns (`superpowers/skills/subagent-driven-development`,
  `superpowers/skills/systematic-debugging`,
  `superpowers/skills/verification-before-completion`).
- **Autoresearch** ([uditgoenka/autoresearch](https://github.com/uditgoenka/autoresearch)) —
  optimization-loop patterns referenced in skill descriptions.

Each upstream skill file retains its original attribution where applicable.
For exact upstream license terms, see those repositories.

## Original work

Everything else in this repo — the lifecycle scripts, classifiers, validators,
the self-improvement loop, the meta-pattern (harness-propose / harness-review),
adapter system, installer, Docker setup, doctor, benchmark runner, and the
overall architectural composition — is original work covered by the MIT
license in `LICENSE`.
