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

# Per-phase timeouts (seconds). Set to 0 to disable. Override via env.
_EXPLORER_TIMEOUT="${KIT_BUILD_EXPLORER_TIMEOUT:-180}"
_IMPLEMENT_TIMEOUT="${KIT_BUILD_IMPLEMENT_TIMEOUT:-360}"
_REVIEW_TIMEOUT="${KIT_BUILD_REVIEW_TIMEOUT:-180}"

kit_log_header "kit-build" "goal" "$GOAL"
kit_log "kit-build: timeouts explorer=${_EXPLORER_TIMEOUT}s implement=${_IMPLEMENT_TIMEOUT}s review=${_REVIEW_TIMEOUT}s"

# Phase 1 -- explore (skipped for trivially-scoped single-file goals)
kit_announce_agent "workflow-explorer" "map code surface for: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "map code surface" "started"
_phase1_start=$(date +%s)
_hb=$(kit_heartbeat_start)

if kit_is_trivial_goal "$GOAL"; then
    kit_log "kit-build: trivial goal detected -- fast-pathing explorer"
    printf '# Fast-path explore (trivial goal)\n\nGoal: %s\n\nNo deep exploration needed for trivially-scoped goals.\n' "$GOAL" > "$SESSION_DIR/explore.md"
    _phase1_status="skipped"
else
    _phase1_rc=0
    kit_copilot_timed "$_EXPLORER_TIMEOUT" --agent workflow-explorer \
        -p "Map the code surface relevant to: $GOAL. Return: 3-5 likely files, integration points, conventions to follow." \
        $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/explore.md" || _phase1_rc=$?
    if [ "$_phase1_rc" -eq 124 ]; then
        kit_log "WARN -- workflow-explorer timed out after ${_EXPLORER_TIMEOUT}s; continuing with partial context"
        printf '\n\n---\nWARN: explorer timed out after %ss.\n' "$_EXPLORER_TIMEOUT" >> "$SESSION_DIR/explore.md"
        _phase1_status="timed-out"
    elif [ "$_phase1_rc" -ne 0 ]; then
        kit_heartbeat_stop "$_hb"
        kit_record_subagent "$SESSION_DIR" "workflow-explorer" "map code surface (exit=$_phase1_rc)" "failed"
        exit "$_phase1_rc"
    else
        _phase1_status="done"
    fi
fi

kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "map code surface" "${_phase1_status:-done}"
kit_done_agent "workflow-explorer" "$(($(date +%s) - _phase1_start))"

# Phase 2 -- implement (hard timeout; failure here is fatal)
kit_announce_agent "workflow-implementer" "implement: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "implement goal" "started"
_phase2_start=$(date +%s)
_hb=$(kit_heartbeat_start)
_phase2_rc=0
kit_copilot_timed "$_IMPLEMENT_TIMEOUT" --agent workflow-implementer \
    -p "Implement: $GOAL. Context from explorer is at $SESSION_DIR/explore.md. Run the project's test command after editing and report exit code." \
    $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/implement.md" || _phase2_rc=$?
kit_heartbeat_stop "$_hb"
if [ "$_phase2_rc" -eq 124 ]; then
    kit_record_subagent "$SESSION_DIR" "workflow-implementer" "implement goal (timed-out after ${_IMPLEMENT_TIMEOUT}s)" "failed"
    kit_log "ERROR -- workflow-implementer timed out after ${_IMPLEMENT_TIMEOUT}s; set KIT_BUILD_IMPLEMENT_TIMEOUT to increase"
    exit 124
elif [ "$_phase2_rc" -ne 0 ]; then
    kit_record_subagent "$SESSION_DIR" "workflow-implementer" "implement goal (exit=$_phase2_rc)" "failed"
    exit "$_phase2_rc"
fi
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "implement goal" "done"
kit_done_agent "workflow-implementer" "$(($(date +%s) - _phase2_start))"

# Phase 3 -- review (parallel, non-blocking on timeout/failure)
echo "kit-build: Phase 3 -- spawning parallel review agents..." >&2
kit_announce_agent "code-quality-reviewer + security-reviewer" "review the diff (parallel)"
kit_record_subagent "$SESSION_DIR" "code-quality-reviewer" "review diff" "started"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "security review diff" "started"
_phase3_start=$(date +%s)
_hb=$(kit_heartbeat_start)
kit_copilot_timed "$_REVIEW_TIMEOUT" --agent code-quality-reviewer -p "Review the diff in this repo against goal: $GOAL. Tag findings BLOCKING/NON-BLOCKING/NIT." $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/review-quality.md" &
QPID=$!
kit_copilot_timed "$_REVIEW_TIMEOUT" --agent security-reviewer -p "Security review of the diff. Same tag scheme." $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/review-security.md" &
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
# Review phase is informational; log failures but do not abort the workflow.
if [ "$_phase3_exit" -ne 0 ]; then
    kit_log "WARN -- review phase reported failures (exit=$_phase3_exit); check review-*.md for details"
fi

echo "kit-build: review reports at $SESSION_DIR/review-{quality,security}.md" >&2
echo "kit-build: ensure verification (tests/lint/build) is green before treating this as done." >&2
