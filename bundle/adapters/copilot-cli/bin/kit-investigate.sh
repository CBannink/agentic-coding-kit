#!/usr/bin/env bash
# kit-investigate -- hypothesis-driven investigation, evidence-only (no code changes).
# Produces a Build Brief that kit-build can consume.
# Usage: kit-investigate "<symptom description>"
set -e
GOAL="${1:?Usage: kit-investigate '<symptom>'}"
SESSION_DIR="${HOME}/.agents/session-state/$(date +%Y%m%d-%H%M%S)-investigate"
mkdir -p "$SESSION_DIR"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

copilot --agent workflow-explorer -p "Investigate: $GOAL. Output: 3-5 hypotheses ranked by likelihood, each with the cheapest test to confirm or eliminate." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/hypotheses.md"

copilot --agent workflow-explorer -p "Run the cheapest tests from $SESSION_DIR/hypotheses.md and report which hypotheses are supported / eliminated by direct evidence (file:line, log excerpt, command output)." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/evidence.md"

cat > "$SESSION_DIR/build-brief.md" <<BRIEF
## Build Brief $(date +%Y-%m-%d)
- **Symptom**: $GOAL
- **Investigation**: see hypotheses.md + evidence.md in this directory
- **Recommended fix**: see evidence.md root-cause section
BRIEF

echo "kit-investigate: Build Brief at $SESSION_DIR/build-brief.md" >&2
echo "kit-investigate: pass to kit-build to fix once root cause is confirmed" >&2
