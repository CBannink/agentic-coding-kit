# /build

Read and follow `__SKILL_ROOT__/build/SKILL.md` exactly.

__HOST_NAME__ adapter note:

1. This command is a workflow entrypoint, not a general chat shortcut.
2. The installed workflow agents (`workflow-explorer`, `workflow-implementer`,
   `workflow-reviewer`, `workflow-skeptic`, `workflow-ui-qa`) are the
   __HOST_NAME__ transport layer for the shared build workflow.
3. Use `workflow-explorer` for cheap exploration and the delegated
   implementation/review agents for non-trivial work.
4. Do not keep non-trivial source reads or multi-file code edits inline in the
   main session when the installed workflow agents are available.
