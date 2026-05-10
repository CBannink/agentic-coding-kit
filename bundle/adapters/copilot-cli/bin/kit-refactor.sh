#!/usr/bin/env bash
# kit-refactor -- behavior-equivalence-gated refactor pipeline.
# Usage: kit-refactor "<refactor goal>"
set -e
GOAL="${1:?Usage: kit-refactor '<goal>'}"
SESSION_DIR="${HOME}/.agents/session-state/$(date +%Y%m%d-%H%M%S)-refactor"
mkdir -p "$SESSION_DIR"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

copilot --agent workflow-explorer -p "Refactor consequence trace for: $GOAL. Map all call sites of the code being restructured, affected tests, public APIs that must NOT change." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/consequences.md"

copilot --agent workflow-implementer -p "Refactor: $GOAL. Behavior MUST be identical. Run the test suite before and after; both must pass with the SAME pass count and coverage. Context at $SESSION_DIR/consequences.md" $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/implement.md"

copilot --agent code-quality-reviewer -p "REFACTOR review: verify behavior is unchanged. Original tests still asserting? Public APIs untouched? Every error path preserved? Look for accidental simplifications that change semantics." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/review.md"

copilot --agent modularity-expert -p "Refactor: confirm the principle was achieved. Goal was: $GOAL. Did duplicates consolidate? Are boundaries clean? Was the wrapper deleted?" $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/modularity.md"

echo "kit-refactor: reports at $SESSION_DIR/" >&2
