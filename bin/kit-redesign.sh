#!/usr/bin/env bash
# kit-redesign -- UX/UI critique-driven redesign pipeline.
# Note: playwright-driven before/after screenshot capture is Claude/OpenCode only;
# Copilot version is critique-driven (no automated visual diff).
# Usage: kit-redesign "<what to redesign>"
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"
GOAL="${1:?Usage: kit-redesign '<what to redesign>'}"
SESSION_DIR="$(kit_make_session_dir "redesign")"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

kit_log_header "kit-redesign" "goal" "$GOAL"

kit_announce_agent "ux-driver" "UX critique for: $GOAL"
kit_record_subagent "$SESSION_DIR" "ux-driver" "UX critique" "started"
_ux_start=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent ux-driver -p "UX critique for: $GOAL. Information architecture, scannability, hierarchy, cognitive load, a11y structure." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/ux.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "ux-driver" "UX critique" "done"
kit_done_agent "ux-driver" "$(($(date +%s) - _ux_start))"

kit_announce_agent "ui-driver" "UI critique for: $GOAL"
kit_record_subagent "$SESSION_DIR" "ui-driver" "UI critique" "started"
_ui_start=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent ui-driver -p "UI critique (visual polish) for: $GOAL. Typography, color, spacing, density, motion, AI-slop pattern detection." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/ui.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "ui-driver" "UI critique" "done"
kit_done_agent "ui-driver" "$(($(date +%s) - _ui_start))"

kit_announce_agent "workflow-implementer" "implement redesign for: $GOAL"
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "implement redesign" "started"
_impl_start=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-implementer -p "Implement the redesign for: $GOAL. UX feedback at $SESSION_DIR/ux.md. UI feedback at $SESSION_DIR/ui.md. Apply the changes and run any visual tests if present." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/implement.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "implement redesign" "done"
kit_done_agent "workflow-implementer" "$(($(date +%s) - _impl_start))"

kit_log "kit-redesign: see $SESSION_DIR/ for UX+UI critiques"
kit_log "kit-redesign: NOTE -- playwright-driven before/after screenshot capture is Claude/OpenCode only"
