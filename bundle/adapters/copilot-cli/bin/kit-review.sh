#!/usr/bin/env bash
# kit-review -- hierarchical review pipeline composed via Copilot CLI shell calls.
# Usage: kit-review "<context: which diff / what concern>"
set -e
GOAL="${1:?Usage: kit-review '<diff context>'}"
SESSION_DIR="${HOME}/.agents/session-state/$(date +%Y%m%d-%H%M%S)-review"
mkdir -p "$SESSION_DIR"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

# Surface review (parallel)
copilot --agent code-quality-reviewer -p "Review the current diff. Goal context: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/quality.md" &
QPID=$!
copilot --agent security-reviewer -p "Security review of the current diff. Context: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/security.md" &
SPID=$!
copilot --agent modularity-expert -p "Architecture/modularity review of the current diff. Context: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/modularity.md" &
MPID=$!
wait $QPID $SPID $MPID

# Adversarial pass
copilot --agent adversarial-reviewer -p "Adversarial review of the current diff. Surface findings the others missed. Context: $GOAL" $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/adversarial.md"

echo "kit-review: reports at $SESSION_DIR/" >&2
