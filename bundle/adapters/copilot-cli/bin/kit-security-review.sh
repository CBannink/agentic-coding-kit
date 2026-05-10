#!/usr/bin/env bash
# kit-security-review -- adversarial security audit fan-out by attack class.
# Usage: kit-security-review "<scope: whole repo / specific diff / specific concern>"
set -e
GOAL="${1:?Usage: kit-security-review '<scope>'}"
SESSION_DIR="${HOME}/.agents/session-state/$(date +%Y%m%d-%H%M%S)-secrev"
mkdir -p "$SESSION_DIR"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

# Authorization gate
echo "kit-security-review: this is YOUR code / YOUR repo / authorized engagement?" >&2
echo "Press Ctrl-C to abort, Enter to continue." >&2
read -r _

# Parallel attack-class fan-out
copilot --agent security-reviewer -p "Injection review (SQL, command, path traversal, template, NoSQL, prompt injection) for: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/injection.md" &
P1=$!
copilot --agent security-reviewer -p "AuthN/AuthZ review (broken auth, missing checks, IDOR, privilege escalation) for: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/auth.md" &
P2=$!
copilot --agent security-reviewer -p "Secrets review (hardcoded keys, leaked tokens, weak crypto, predictable randomness) for: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/secrets.md" &
P3=$!
copilot --agent security-reviewer -p "Business logic review (race conditions, TOCTOU, state machine bugs, missing rate limits) for: $GOAL" $NOASK_FLAG --allow-all-tools > "$SESSION_DIR/biz-logic.md" &
P4=$!
wait $P1 $P2 $P3 $P4

# Synthesis
copilot -p "Synthesize the security findings in $SESSION_DIR/{injection,auth,secrets,biz-logic}.md into one consolidated report. Tag CRITICAL/HIGH/MEDIUM/LOW with file:line and concrete remediation. Add an authorization-context disclaimer (this was a review of YOUR code per the gate above)." $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/SYNTHESIS.md"

echo "kit-security-review: synthesis at $SESSION_DIR/SYNTHESIS.md" >&2
