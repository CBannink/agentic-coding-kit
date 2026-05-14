#!/usr/bin/env bash
# kit-investigate -- hypothesis-driven investigation, evidence-only (no code changes).
# Produces a Build Brief that kit-build can consume.
# Usage: kit-investigate "<symptom description>"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"
GOAL="${1:?Usage: kit-investigate '<symptom>'}"
SESSION_DIR="$(kit_make_session_dir "investigate")"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

kit_log_header "kit-investigate" "symptom" "$GOAL"

kit_announce_agent "workflow-explorer" "generate hypotheses for: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "generate hypotheses" "started"
_h1=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-explorer -p "Investigate: $GOAL. Output: 3-5 hypotheses ranked by likelihood, each with the cheapest test to confirm or eliminate." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/hypotheses.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "generate hypotheses" "done"
kit_done_agent "workflow-explorer" "$(($(date +%s) - _h1))"

kit_announce_agent "workflow-explorer" "run cheapest tests from hypotheses.md"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "eliminate hypotheses with evidence" "started"
_h2=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-explorer -p "Run the cheapest tests from $SESSION_DIR/hypotheses.md and report which hypotheses are supported / eliminated by direct evidence (file:line, log excerpt, command output)." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/evidence.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-explorer" "eliminate hypotheses with evidence" "done"
kit_done_agent "workflow-explorer (evidence)" "$(($(date +%s) - _h2))"

cat > "$SESSION_DIR/build-brief.md" <<BRIEF
## Build Brief $(date +%Y-%m-%d)
- **Symptom**: $GOAL
- **Investigation**: see hypotheses.md + evidence.md in this directory
- **Recommended fix**: see evidence.md root-cause section
BRIEF

echo "kit-investigate: Build Brief at $SESSION_DIR/build-brief.md" >&2
echo "kit-investigate: pass to kit-build to fix once root cause is confirmed" >&2
