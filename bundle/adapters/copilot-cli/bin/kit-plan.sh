#!/usr/bin/env bash
# kit-plan -- plan-first workflow. Produces plan.md, stops for user approval.
# Usage: kit-plan "<task to plan>"
set -e
GOAL="${1:?Usage: kit-plan '<task>'}"
SESSION_DIR="${HOME}/.agents/session-state/$(date +%Y%m%d-%H%M%S)-plan"
mkdir -p "$SESSION_DIR"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

copilot --agent workflow-explorer -p "Map repo context for planning: $GOAL. Return existing patterns, test conventions, integration points, files likely to change." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/context.md"

copilot --agent workflow-skeptic -p "Pressure-test this plan goal: $GOAL. Context at $SESSION_DIR/context.md. Challenge: is this the right problem? Simpler approach? Failure modes?" $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/skeptic.md"

copilot -p "Write a plan.md at $SESSION_DIR/plan.md for goal: $GOAL. Sections: Goal, Approach, Files (planned changes), Out of scope, Verification (test command + expected), Risks/open questions. Use the explorer context and skeptic feedback above." $NOASK_FLAG --allow-all-tools

echo "kit-plan: plan written to $SESSION_DIR/plan.md" >&2
echo "kit-plan: review then run kit-build to execute" >&2
