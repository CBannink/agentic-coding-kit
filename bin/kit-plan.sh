#!/usr/bin/env bash
# kit-plan -- plan-first workflow. Produces plan.md, stops for user approval.
# Usage: kit-plan "<task to plan>"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"
GOAL="${1:?Usage: kit-plan '<task>'}"
SESSION_DIR="$(kit_make_session_dir "plan")"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

kit_log_header "kit-plan" "task" "$GOAL"

kit_announce_agent "workflow-explorer" "map repo context for planning: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "map planning context" "started"
_p1=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-explorer -p "Map repo context for planning: $GOAL. Return existing patterns, test conventions, integration points, files likely to change." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/context.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "map planning context" "done"
kit_done_agent "workflow-explorer" "$(($(date +%s) - _p1))"

kit_announce_agent "workflow-skeptic" "pressure-test plan: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-skeptic" "pressure-test plan" "started"
_p2=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-skeptic -p "Pressure-test this plan goal: $GOAL. Context at $SESSION_DIR/context.md. Challenge: is this the right problem? Simpler approach? Failure modes?" $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/skeptic.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-skeptic" "pressure-test plan" "done"
kit_done_agent "workflow-skeptic" "$(($(date +%s) - _p2))"

kit_announce_agent "copilot (synthesis)" "write plan.md"
kit_record_subagent "$SESSION_DIR" "copilot" "write plan" "started"
_p3=$(date +%s)
_hb=$(kit_heartbeat_start)
_plan_exit=0
_plan_status="done"
_plan_task="write plan"
if copilot -p "Write a plan.md at $SESSION_DIR/plan.md for goal: $GOAL. Sections: Goal, Approach, Files (planned changes), Out of scope, Verification (test command + expected), Risks/open questions. Use the explorer context and skeptic feedback above." $NOASK_FLAG --allow-all-tools; then
    :
else
    _plan_exit=$?
    _plan_status="failed"
    _plan_task="write plan (exit=$_plan_exit)"
fi
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "copilot" "$_plan_task" "$_plan_status"
kit_done_agent "copilot (synthesis)" "$(($(date +%s) - _p3))"
[ "$_plan_exit" -eq 0 ] || exit "$_plan_exit"

echo "kit-plan: plan written to $SESSION_DIR/plan.md" >&2
echo "kit-plan: review then run kit-build to execute" >&2
