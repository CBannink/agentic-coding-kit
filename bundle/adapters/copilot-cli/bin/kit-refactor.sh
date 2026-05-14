#!/usr/bin/env bash
# kit-refactor -- behavior-equivalence-gated refactor pipeline.
# Usage: kit-refactor "<refactor goal>"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"
GOAL="${1:?Usage: kit-refactor '<goal>'}"
SESSION_DIR="$(kit_make_session_dir "refactor")"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

kit_log_header "kit-refactor" "goal" "$GOAL"

kit_announce_agent "workflow-explorer" "consequence trace for: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "consequence trace" "started"
_rf1=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-explorer -p "Refactor consequence trace for: $GOAL. Map all call sites of the code being restructured, affected tests, public APIs that must NOT change." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/consequences.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "consequence trace" "done"
kit_done_agent "workflow-explorer" "$(($(date +%s) - _rf1))"

kit_announce_agent "workflow-implementer" "behavior-preserving refactor: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "implement refactor" "started"
_rf2=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-implementer -p "Refactor: $GOAL. Behavior MUST be identical. Run the test suite before and after; both must pass with the SAME pass count and coverage. Context at $SESSION_DIR/consequences.md" $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/implement.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "implement refactor" "done"
kit_done_agent "workflow-implementer" "$(($(date +%s) - _rf2))"

kit_announce_agent "code-quality-reviewer" "verify behavior is unchanged"
kit_record_subagent "$SESSION_DIR" "code-quality-reviewer" "review refactor behavior" "started"
_rf3=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent code-quality-reviewer -p "REFACTOR review: verify behavior is unchanged. Original tests still asserting? Public APIs untouched? Every error path preserved? Look for accidental simplifications that change semantics." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/review.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "code-quality-reviewer" "review refactor behavior" "done"
kit_done_agent "code-quality-reviewer" "$(($(date +%s) - _rf3))"

kit_announce_agent "modularity-expert" "modularity check for: $GOAL"
kit_record_subagent "$SESSION_DIR" "modularity-expert" "modularity check" "started"
_rf4=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent modularity-expert -p "Refactor: confirm the principle was achieved. Goal was: $GOAL. Did duplicates consolidate? Are boundaries clean? Was the wrapper deleted?" $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/modularity.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "modularity-expert" "modularity check" "done"
kit_done_agent "modularity-expert" "$(($(date +%s) - _rf4))"

kit_log "kit-refactor: reports at $SESSION_DIR/"
