# Wiki Page Templates

`index.md` is a routing table: authority notice, repository shape, task-signal
links only to existing pages, workspace links, and durability rule.

`repository-map.md` maps top-level purpose, real entry points, nearest tests,
ownership boundaries, generated/vendor/build output, fixtures, and applicable
"start here" routes without enumerating every file.

`architecture.md` records evidence-backed runtime/process boundaries, control
and data flow, dependency direction, state ownership, API/IPC/integration
boundaries, jobs/loops/retries, and production-critical failure behavior.

`engineering.md` contains only verified install/develop/test/type/lint/build
commands, environment/setup, repository-specific conventions, testing patterns,
change-type verification selection, and confirmed recurring traps.

Optional area pages use valid YAML frontmatter with `use_when` and existing
`source_paths`, then purpose, flow, interfaces, invariants, reusable patterns,
verification, traps, and useful related pages.
