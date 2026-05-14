#!/usr/bin/env bash
# kit-review -- hierarchical review pipeline composed via Copilot CLI shell calls.
# Usage: kit-review "<context: which diff / what concern>"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"
GOAL="${1:?Usage: kit-review '<diff context>'}"
SESSION_DIR="$(kit_make_session_dir "review")"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

kit_log_header "kit-review" "goal" "$GOAL"

# Surface review (parallel)
echo "kit-review: spawning 3 parallel review agents..." >&2
kit_announce_agent "code-quality-reviewer + security-reviewer + modularity-expert" "surface review (parallel)"
kit_record_subagent "$SESSION_DIR" "code-quality-reviewer" "review diff: $GOAL" "started"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "security review: $GOAL" "started"
kit_record_subagent "$SESSION_DIR" "modularity-expert" "modularity review: $GOAL" "started"
_surf_start=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent code-quality-reviewer -p "Review the current diff. Goal context: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/quality.md" &
QPID=$!
copilot --agent security-reviewer -p "Security review of the current diff. Context: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/security.md" &
SPID=$!
copilot --agent modularity-expert -p "Architecture/modularity review of the current diff. Context: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/modularity.md" &
MPID=$!
_surface_exit=0
_quality_status="done"
_quality_task="review diff: $GOAL"
if wait "$QPID"; then
    :
else
    _surface_exit=$?
    _quality_status="failed"
    _quality_task="review diff: $GOAL (exit=$_surface_exit)"
fi
_security_status="done"
_security_task="security review: $GOAL"
if wait "$SPID"; then
    :
else
    _security_exit=$?
    _security_status="failed"
    _security_task="security review: $GOAL (exit=$_security_exit)"
    if [ "$_surface_exit" -eq 0 ]; then
        _surface_exit=$_security_exit
    fi
fi
_modularity_status="done"
_modularity_task="modularity review: $GOAL"
if wait "$MPID"; then
    :
else
    _modularity_exit=$?
    _modularity_status="failed"
    _modularity_task="modularity review: $GOAL (exit=$_modularity_exit)"
    if [ "$_surface_exit" -eq 0 ]; then
        _surface_exit=$_modularity_exit
    fi
fi
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "code-quality-reviewer" "$_quality_task" "$_quality_status"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "$_security_task" "$_security_status"
kit_record_subagent "$SESSION_DIR" "modularity-expert" "$_modularity_task" "$_modularity_status"
kit_done_agent "surface review" "$(($(date +%s) - _surf_start))"
[ "$_surface_exit" -eq 0 ] || exit "$_surface_exit"

# Adversarial pass
kit_announce_agent "adversarial-reviewer" "adversarial pass: $GOAL"
kit_record_subagent "$SESSION_DIR" "adversarial-reviewer" "adversarial review: $GOAL" "started"
_adv_start=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent adversarial-reviewer -p "Adversarial review of the current diff. Surface findings the others missed. Context: $GOAL" $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/adversarial.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "adversarial-reviewer" "adversarial review: $GOAL" "done"
kit_done_agent "adversarial-reviewer" "$(($(date +%s) - _adv_start))"

echo "kit-review: reports at $SESSION_DIR/" >&2
