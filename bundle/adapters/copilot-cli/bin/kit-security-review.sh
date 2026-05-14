#!/usr/bin/env bash
# kit-security-review -- adversarial security audit fan-out by attack class.
# Usage: kit-security-review "<scope: whole repo / specific diff / specific concern>"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"
GOAL="${1:?Usage: kit-security-review '<scope>'}"
SESSION_DIR="$(kit_make_session_dir "secrev")"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

kit_log_header "kit-security-review" "goal" "$GOAL"

# Authorization gate
kit_log "kit-security-review: authorization gate -- use only on your code / your repo / an authorized engagement."
if [ "${KIT_COPILOT_INTERACTIVE_AUTH:-0}" = "1" ]; then
    kit_log "kit-security-review: interactive confirmation enabled; press Ctrl-C to abort or Enter to continue."
    read -r _
else
    kit_log "kit-security-review: non-interactive mode -- proceeding without prompt. Set KIT_COPILOT_INTERACTIVE_AUTH=1 to require confirmation."
fi

# Parallel attack-class fan-out
kit_announce_agent "security-reviewer x4" "parallel attack-class review for: $GOAL"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "injection review" "started"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "auth review" "started"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "secrets review" "started"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "business-logic review" "started"
_sec1=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent security-reviewer -p "Injection review (SQL, command, path traversal, template, NoSQL, prompt injection) for: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/injection.md" &
P1=$!
copilot --agent security-reviewer -p "AuthN/AuthZ review (broken auth, missing checks, IDOR, privilege escalation) for: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/auth.md" &
P2=$!
copilot --agent security-reviewer -p "Secrets review (hardcoded keys, leaked tokens, weak crypto, predictable randomness) for: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/secrets.md" &
P3=$!
copilot --agent security-reviewer -p "Business logic review (race conditions, TOCTOU, state machine bugs, missing rate limits) for: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/biz-logic.md" &
P4=$!
wait $P1 $P2 $P3 $P4
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "injection review" "done"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "auth review" "done"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "secrets review" "done"
kit_record_subagent "$SESSION_DIR" "security-reviewer" "business-logic review" "done"
kit_done_agent "security-reviewer x4" "$(($(date +%s) - _sec1))"

# Synthesis
kit_announce_agent "copilot (synthesis)" "synthesize security findings"
kit_record_subagent "$SESSION_DIR" "copilot" "synthesize security findings" "started"
_sec2=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot -p "Synthesize the security findings in $SESSION_DIR/{injection,auth,secrets,biz-logic}.md into one consolidated report. Tag CRITICAL/HIGH/MEDIUM/LOW with file:line and concrete remediation. Add an authorization-context disclaimer (this was a review of YOUR code per the gate above)." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/SYNTHESIS.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "copilot" "synthesize security findings" "done"
kit_done_agent "copilot (synthesis)" "$(($(date +%s) - _sec2))"

kit_log "kit-security-review: synthesis at $SESSION_DIR/SYNTHESIS.md"
