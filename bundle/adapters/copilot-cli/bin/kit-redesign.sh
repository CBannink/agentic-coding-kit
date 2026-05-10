#!/usr/bin/env bash
# kit-redesign -- UX/UI critique-driven redesign pipeline.
# Note: playwright-driven before/after screenshot capture is Claude/OpenCode only;
# Copilot version is critique-driven (no automated visual diff).
# Usage: kit-redesign "<what to redesign>"
set -e
GOAL="${1:?Usage: kit-redesign '<what to redesign>'}"
SESSION_DIR="${HOME}/.agents/session-state/$(date +%Y%m%d-%H%M%S)-redesign"
mkdir -p "$SESSION_DIR"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

copilot --agent ux-driver -p "UX critique for: $GOAL. Information architecture, scannability, hierarchy, cognitive load, a11y structure." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/ux.md"

copilot --agent ui-driver -p "UI critique (visual polish) for: $GOAL. Typography, color, spacing, density, motion, AI-slop pattern detection." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/ui.md"

copilot --agent workflow-implementer -p "Implement the redesign for: $GOAL. UX feedback at $SESSION_DIR/ux.md. UI feedback at $SESSION_DIR/ui.md. Apply the changes and run any visual tests if present." $NOASK_FLAG --allow-all-tools

echo "kit-redesign: see $SESSION_DIR/ for UX+UI critiques" >&2
echo "kit-redesign: NOTE -- playwright-driven before/after screenshot capture is Claude/OpenCode only" >&2
