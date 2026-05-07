# /plan

Read and follow `__SKILL_ROOT__/plan/SKILL.md` exactly.

__HOST_NAME__ adapter note:

1. This command is the approval gate for non-trivial `/build` work.
2. Keep exploration cheap; if planning needs more than two source-file reads,
   delegate to `workflow-explorer` instead of excavating inline in the main session.
3. Do not start implementation until the plan artifact is approved.

Produce an approval-ready build plan.

You must:
1. inspect repo context
2. identify likely files to change
3. trace blast radius when needed
4. pressure-test the plan
5. stop for approval before implementation
