#!/usr/bin/env bash
# kit-analyze -- multi-angle research / comparison / evaluation workflow.
# Usage: kit-analyze "<question or topic>"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"
GOAL="${1:?Usage: kit-analyze '<question or topic>'}"
SESSION_DIR="$(kit_make_session_dir "analyze")"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

kit_log_header "kit-analyze" "topic" "$GOAL"

kit_announce_agent "workflow-explorer" "explore codebase surface for: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "explore analysis surface" "started"
_a1=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-explorer -p "Analyze: $GOAL. Return the relevant code/docs surface, current behavior, constraints, tradeoffs, and evidence to inspect. Keep facts separate from recommendations." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/explore.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "explore analysis surface" "done"
kit_done_agent "workflow-explorer" "$(($(date +%s) - _a1))"

kit_announce_agent "workflow-skeptic" "challenge analysis: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-skeptic" "challenge analysis" "started"
_a2=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-skeptic -p "Challenge this analysis topic: $GOAL. Context at $SESSION_DIR/explore.md. Surface alternative interpretations, missing evidence, risks, and what would change the conclusion." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/skeptic.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-skeptic" "challenge analysis" "done"
kit_done_agent "workflow-skeptic" "$(($(date +%s) - _a2))"

kit_announce_agent "copilot (synthesis)" "write analysis report"
kit_record_subagent "$SESSION_DIR" "copilot" "synthesize analysis report" "started"
_a3=$(date +%s)
_hb=$(kit_heartbeat_start)
_synth_exit=0
_synth_status="done"
_synth_task="synthesize analysis report"
if copilot -p "Write an analysis report at $SESSION_DIR/analysis.md for topic: $GOAL. Use $SESSION_DIR/explore.md and $SESSION_DIR/skeptic.md. Sections: Question, Facts, Tradeoffs, Recommended path, Evidence gaps, Follow-up commands. Keep assumptions explicit." $NOASK_FLAG --allow-all-tools; then
    :
else
    _synth_exit=$?
    _synth_status="failed"
    _synth_task="synthesize analysis report (exit=$_synth_exit)"
fi
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "copilot" "$_synth_task" "$_synth_status"
kit_done_agent "copilot (synthesis)" "$(($(date +%s) - _a3))"
[ "$_synth_exit" -eq 0 ] || exit "$_synth_exit"

echo "kit-analyze: report written to $SESSION_DIR/analysis.md" >&2
echo "kit-analyze: use kit-build if this analysis becomes an implementation task" >&2
