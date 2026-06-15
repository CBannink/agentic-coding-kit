---
name: experts-silent-failure-hunter
description: "Deprecated compatibility alias. Use the top-level silent-failure-hunter skill instead."
---

# Silent Failure Hunter Compatibility Alias

This nested expert skill is kept so older references do not break.

For new work, load:

`~/.agents/skills/silent-failure-hunter/SKILL.md`

The canonical skill is a focused lazy review lens for swallowed errors,
dangerous fallbacks, missing logging context, unobserved promises, and lost CLI
exit failures. It is not a default agent and should only be loaded when the diff
touches relevant failure paths.
