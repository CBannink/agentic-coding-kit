#!/usr/bin/env bash
# kit-build -- Copilot CLI shell-script workflow.
#
# Copilot CLI is command-based, not in-session orchestration like Claude Code.
# Per https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/automate-with-actions
# the canonical multi-step pattern is bash chaining of `copilot --agent X -p` calls.
#
# Usage: kit-build "<your request>"
# Optional env: KIT_COPILOT_NOASK=0 to disable --no-ask-user

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"
GOAL="${1:?Usage: kit-build '<request>'}"
SESSION_DIR="$(kit_make_session_dir "build")"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

kit_log_header "kit-build" "goal" "$GOAL"

# Phase 1 -- explore
kit_announce_agent "workflow-explorer" "map code surface for: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "map code surface" "started"
_phase1_start=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-explorer -p "Map the code surface relevant to: $GOAL. Return: 3-5 likely files, integration points, conventions to follow." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/explore.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "map code surface" "done"
kit_done_agent "workflow-explorer" "$(($(date +%s) - _phase1_start))"

# Phase 2 -- implement
kit_announce_agent "workflow-implementer" "implement: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "implement goal" "started"
_phase2_start=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-implementer -p "Implement: $GOAL. Context from explorer is at $SESSION_DIR/explore.md. Run the project's test command after editing and report exit code." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/implement.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "implement goal" "done"
kit_done_agent "workflow-implementer" "$(($(date +%s) - _phase2_start))"

# Phase 3 -- review (parallel)
echo "kit-build: Phase 3 -- spawning parallel review agents..." >&2
kit_announce_agent "code-quality-reviewer + security-reviewer" "review the diff (parallel)"
kit_record_subagent "$SESSION_DIR" "code-quality-reviewer" "review diff" "started"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "security review diff" "started"
_phase3_start=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent code-quality-reviewer -p "Review the diff in this repo against goal: $GOAL. Tag findings BLOCKING/NON-BLOCKING/NIT." $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/review-quality.md" &
QPID=$!
copilot --agent security-reviewer -p "Security review of the diff. Same tag scheme." $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/review-security.md" &
SPID=$!
_phase3_exit=0
_quality_status="done"
_quality_task="review diff"
if wait "$QPID"; then
    :
else
    _phase3_exit=$?
    _quality_status="failed"
    _quality_task="review diff (exit=$_phase3_exit)"
fi
_security_status="done"
_security_task="security review diff"
if wait "$SPID"; then
    :
else
    _security_exit=$?
    _security_status="failed"
    _security_task="security review diff (exit=$_security_exit)"
    if [ "$_phase3_exit" -eq 0 ]; then
        _phase3_exit=$_security_exit
    fi
fi
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "code-quality-reviewer" "$_quality_task" "$_quality_status"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "$_security_task" "$_security_status"
kit_done_agent "code-quality-reviewer + security-reviewer" "$(($(date +%s) - _phase3_start))"
[ "$_phase3_exit" -eq 0 ] || exit "$_phase3_exit"

echo "kit-build: review reports at $SESSION_DIR/review-{quality,security}.md" >&2
echo "kit-build: ensure verification (tests/lint/build) is green before treating this as done." >&2
