---
name: wiki
description: Initialize, reinitialize, or audit curated repository engineering knowledge.
---

# Wiki

Support only `init`, `reinit`, and read-only `audit`. Current source and
executable behavior remain authoritative. Normal work never edits `.wiki`.

The wiki is compact, progressively disclosed repository navigation, not memory,
reflection, task history, handoff state, hidden instructions, a feature
inventory, or standalone proof. Follow its citations into live source.

For init or reinit:

```text
deterministic inventory
-> one Orientation Scout
-> focused page discovery for repository map, engineering, coding, reviewing,
   testing, and security
-> primary synthesis
-> one fresh independent evidence Reviewer over every page draft
-> at most one focused correction Scout
-> final index synthesis from reviewed summaries and routes
-> deterministic managed write with `kit wiki init --synthesis` or
   `kit wiki reinit --synthesis`
-> primary separately runs mandatory `kit wiki audit`
```

Every material claim cites tracked canonical source and symbols. A convention
needs an authoritative repository source or two independent current-code
examples. Unsupported patterns are omitted. Source wins on conflict.

Every wiki root has exactly these standard pages: `index.md`,
`repository-map.md`, `engineering.md`, `coding.md`, `reviewing.md`, `testing.md`,
and `security.md`. Architecture belongs in `engineering.md`; there is no
standard `architecture.md`. Evidence-justified workspace or area pages and
consented PR-history guidance are optional. Generate the minimal index last; it
states source authority and routes task signals to exact sections.

PR history is optional and consented only during init/reinit. Never install
tools or request/store credentials. Reinitializing an unmarked legacy wiki
requires explicit `--adopt-existing`, backup, and confirmation.

Write-mode `kit wiki init` and `kit wiki reinit` require the reviewed
`--synthesis` artifact from this flow, covering all six content pages in every
generated wiki root. A no-synthesis `--dry-run` remains available only for
deterministic inventory and preview; it never creates scaffold pages.
Init/reinit does not perform the final audit. After the managed write succeeds,
the primary must invoke `kit wiki audit` as a separate read-only command and
must not complete the workflow until that audit passes.

Load [init.md](references/init.md), [templates.md](references/templates.md), and
[audit.md](references/audit.md) as applicable. Load
[pr-history.md](references/pr-history.md) only when consented history is used.
