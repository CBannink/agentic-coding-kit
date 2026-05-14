#!/usr/bin/env bash
# kit-pr-review -- Full holistic PR review via the pr-reviewer agent.
#
# This is distinct from kit-review (diff-only code review):
#   - kit-review: quality + security + modularity + adversarial pass on a diff
#   - kit-pr-review: full PR review (title, description, commits, diff, CI,
#                    repo conventions) → APPROVE / REQUEST_CHANGES / COMMENT
#
# Usage: kit-pr-review [PR_NUMBER_OR_CONTEXT]
# Examples:
#   kit-pr-review                        # review current branch vs main
#   kit-pr-review 42                     # review PR #42
#   kit-pr-review "review the auth PR"   # free-text context
#
# Can also be called as a CI/CD step:
#   bash ~/.agents/bin/copilot/kit-pr-review.sh "$PR_NUMBER"
#
# Exit code 0 = ran to completion; check pr-review.md for APPROVE/REQUEST_CHANGES/COMMENT.
#
# Phase 1E-CI: This wrapper enforces knowledge injection at the CODE level — not
# by prompting the agent. Steps:
#   1. git fetch origin main --depth=1   (shallow-clone mitigation)
#   2. Read each knowledge file per source rules (origin/main preferred)
#   3. Export KNOWLEDGE_CONTEXT env var with the injected content
#   4. Invoke the agent — it receives the knowledge as injected context
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"

PR_CTX="${1:-Review the current branch diff against the default branch. Identify: title, description, commits, diff, CI status, and repo conventions.}"
SESSION_DIR="$(kit_make_session_dir "pr-review")"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

# ---------------------------------------------------------------------------
# Phase 1E-CI: Deterministic knowledge injection (code-level enforcement)
# The agent is NOT told to run git show — we inject the content here so the
# knowledge source is controlled by this script, not by the LLM.
# ---------------------------------------------------------------------------
kit_log "kit-pr-review: fetching origin/main for knowledge injection..."
git fetch origin main --depth=1 2>/dev/null || true

# Knowledge files to inject — ordered by importance
KNOWLEDGE_FILES=(
  ".kit/context/conventions.md"
  ".wiki/architecture.md"
  ".wiki/codebase.md"
  ".wiki/features.md"
  ".kit/context/memory.md"
)

# Get PR-modified files for Rule B override (knowledge files changed in this PR)
PR_MODIFIED=$(git diff origin/main...HEAD --name-only 2>/dev/null || true)

KNOWLEDGE_CONTEXT=""
CONTEXT_SOURCES=""
for KF in "${KNOWLEDGE_FILES[@]}"; do
  CONTENT=""
  SOURCE=""

  # Rule B: if PR modifies this knowledge file, use PR branch version
  if echo "$PR_MODIFIED" | grep -qF "$KF"; then
    CONTENT=$(git show "HEAD:${KF}" 2>/dev/null || true)
    if [ -n "$CONTENT" ]; then
      SOURCE="PR branch (PR modifies this file)"
    fi
  fi

  # Rule A: prefer origin/main
  if [ -z "$CONTENT" ]; then
    CONTENT=$(git show "origin/main:${KF}" 2>/dev/null || true)
    if [ -n "$CONTENT" ]; then
      SOURCE="origin/main"
    fi
  fi

  # Fallback: local checkout
  if [ -z "$CONTENT" ] && [ -f "$KF" ]; then
    CONTENT=$(cat "$KF")
    SOURCE="local checkout (fallback)"
  fi

  if [ -n "$CONTENT" ]; then
    KNOWLEDGE_CONTEXT="${KNOWLEDGE_CONTEXT}
### ${KF} [${SOURCE}]
${CONTENT}

"
    CONTEXT_SOURCES="${CONTEXT_SOURCES}${KF}: ${SOURCE}; "
    kit_log "kit-pr-review: loaded ${KF} from ${SOURCE}"
  fi
done

if [ -z "$KNOWLEDGE_CONTEXT" ]; then
  kit_log "kit-pr-review: WARNING — no knowledge files found on origin/main or local checkout"
fi

# Staleness check: warn if no knowledge file was updated in 60 days
STALE_CHECK=$(git log --since="60.days" --name-only --pretty=format: -- .wiki/ .kit/context/ 2>/dev/null | tr -d '[:space:]')
STALENESS_NOTE=""
if [ -z "$STALE_CHECK" ]; then
  STALENESS_NOTE="⚠️ KNOWLEDGE_STALE: no .wiki/.kit updates in 60+ days — knowledge base may be outdated."
  kit_log "kit-pr-review: $STALENESS_NOTE"
fi

# Build the injected context block to prepend to the agent prompt
INJECTED_CONTEXT="## Repo Knowledge Base (injected from origin/main by kit-pr-review.sh)
Context sources: ${CONTEXT_SOURCES}
${STALENESS_NOTE}

${KNOWLEDGE_CONTEXT}"

# ---------------------------------------------------------------------------

kit_log_header "kit-pr-review" "context" "$PR_CTX"
kit_announce_agent "pr-reviewer" "holistic PR review"
kit_record_subagent "$SESSION_DIR" "pr-reviewer" "holistic PR review" "started"
_pr_start=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent pr-reviewer \
  -p "${INJECTED_CONTEXT}

---

${PR_CTX}. Write the full review to stdout. Include the PR_REVIEW: <verdict> line at the top.
The knowledge base above was injected by kit-pr-review.sh from origin/main.
Do NOT re-read .wiki/ or .kit/context/ files using git show — they are already provided above." \
  $NOASK_FLAG --allow-all-tools \
  | tee "$SESSION_DIR/pr-review.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "pr-reviewer" "holistic PR review" "done"
kit_done_agent "pr-reviewer" "$(($(date +%s) - _pr_start))"

# Extract verdict for CI consumers
VERDICT=$(grep -oP 'PR_REVIEW:\s*\K(APPROVE|REQUEST_CHANGES|COMMENT)' "$SESSION_DIR/pr-review.md" 2>/dev/null || echo "UNKNOWN")
kit_log "kit-pr-review: verdict=$VERDICT"
kit_log "kit-pr-review: full review at $SESSION_DIR/pr-review.md"

# Propagate blocking verdict as non-zero exit for CI gating
if [ "$VERDICT" = "REQUEST_CHANGES" ]; then
  kit_log "kit-pr-review: PR has BLOCKING findings. Exiting non-zero for CI gate."
  exit 2
fi
