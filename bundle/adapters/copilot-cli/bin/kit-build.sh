#!/usr/bin/env bash
# kit-build -- Copilot CLI shell-script workflow.
#
# Copilot CLI is command-based, not in-session orchestration like Claude Code.
# Per https://docs.github.com/en/copilot/how-tos/copilot-cli/automate-copilot-cli/automate-with-actions
# the canonical multi-step pattern is bash chaining of `copilot --agent X -p` calls.
#
# Usage: kit-build "<your request>"
# Optional env: KIT_COPILOT_NOASK=0 to disable --no-ask-user

set -e
GOAL="${1:?Usage: kit-build '<request>'}"
SESSION_DIR="${HOME}/.agents/session-state/$(date +%Y%m%d-%H%M%S)-build"
mkdir -p "$SESSION_DIR"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

echo "kit-build: session=$SESSION_DIR" >&2
echo "kit-build: goal=$GOAL" >&2

# Phase 1 -- explore
copilot --agent workflow-explorer -p "Map the code surface relevant to: $GOAL. Return: 3-5 likely files, integration points, conventions to follow." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/explore.md"

# Phase 2 -- implement
copilot --agent workflow-implementer -p "Implement: $GOAL. Context from explorer is at $SESSION_DIR/explore.md. Run the project's test command after editing and report exit code." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/implement.md"

# Phase 3 -- review (parallel)
copilot --agent code-quality-reviewer -p "Review the diff in this repo against goal: $GOAL. Tag findings BLOCKING/NON-BLOCKING/NIT." $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/review-quality.md" &
QPID=$!
copilot --agent security-reviewer -p "Security review of the diff. Same tag scheme." $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/review-security.md" &
SPID=$!
wait $QPID $SPID

echo "kit-build: review reports at $SESSION_DIR/review-{quality,security}.md" >&2
echo "kit-build: ensure verification (tests/lint/build) is green before treating this as done." >&2
