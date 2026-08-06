---
name: wiki
description: Initialize, reinitialize, or audit curated repository engineering knowledge.
---

# Wiki

Support only `init`, `reinit`, and read-only `audit`. Use ordinary host read,
search, and write tools: no `kit`, PATH setup, CLI, synthesis artifact, `.kit`,
or temporary `.git` workflow state. Current source, configuration, instructions,
and executable behavior are authoritative. The wiki is concise navigation, not
memory, task history, hidden instructions, or standalone proof. Normal work
never edits `.wiki`; only explicit init/reinit may do so.

## Init and reinit

The primary creates `.wiki` if absent, reads every existing wiki file, and
snapshots human content before dispatch. Init fills missing requirements without
replacing existing work. Reinit refreshes source-backed guidance while preserving
unrelated or unclear human files and content. Ask only before a genuinely
destructive replacement, never before creating a required file.

Dispatch exactly one fresh, write-capable host-native specialist (normally
Coder) for each required page. Explicitly label every assignment **Wiki Page
Scout**; this is the Scout and writer, not the normal read-only Repo Scout. The
six content Scouts may run independently because each has one disjoint owned
path. After all six finish, dispatch the seventh/index Scout; it reads the six
completed pages and writes the index.

Every assignment must contain: its exact sole owned path; preservation rules
including the relevant snapshot; required live-source research and
repository-relative path evidence; its page brief below; its token ceiling; and
the stop condition “write this page, verify its ceiling and cited paths, return
only a concise result, edit no other page, and dispatch no successor.” Require
concise bullets/tables, no exploration narrative or repeated obvious facts, and
omission of unsupported content. Ceilings are maxima, not targets; when an exact
tokenizer is unavailable, keep pages concise and comfortably below the ceiling
without adding a tokenizer dependency.

Content pages and briefs:

- `repository-map.md` (800 tokens): purpose; layout/ownership; entry points;
  change routes; canonical/generated boundaries.
- `engineering.md` (800 tokens): architecture; representative control/data
  flows; integrations; errors/lifecycle; operations.
- `coding.md` (800 tokens): demonstrated, token-efficient actionable practices;
  file organization and placement; module/function ordering and inline-versus-
  vertical layout; function naming/responsibility; parameters/defaults/returns;
  control flow and async/error behavior; API/client calls, validation, auth,
  retries; canonical examples.
- `reviewing.md` (800 tokens): repository-specific checks; realistic risks;
  generated/migration boundaries.
- `testing.md` (800 tokens): test layout; commands; fixtures; seams; behavioral
  expectations.
- `security.md` (800 tokens): assets; trust boundaries; auth, input, secrets,
  command, and network controls.

The final `index.md` Scout (500 tokens) covers source authority, concise
summaries, and task routes to exact sections in all six completed pages. State
that source wins on conflict. Use normal headings and repository-relative links
or backticked paths. Architecture belongs in `engineering.md`; never add
`architecture.md`.

At most one optional Reviewer may run after all seven writes. It checks only
required files/basic sections, index links/anchors, cited-path existence, and
token-ceiling compliance. It cannot optimize prose, judge conventions, rewrite,
or trigger another review. The primary makes only mechanical corrections and
rechecks completeness.

## Audit

Make no writes. With ordinary read/search tools, check all required files and
basic sections, token ceilings, local index links/anchors, and repository paths
cited in links or backticks. Report missing items, broken references, and
evident source conflicts; do not repair them.
