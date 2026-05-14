#!/usr/bin/env bash
# kit-goal -- goal-orchestrator entrypoint for Copilot CLI.
# Classifies the goal inline (plain copilot, no agent recursion), routes to the correct kit wrapper.
#
# Usage: kit-goal "<goal>"
# Env overrides:
#   KIT_COPILOT_NOASK=0          -- disable --no-ask-user
#   KIT_GOAL_CLASSIFY_TIMEOUT=90 -- seconds before classify LLM call is killed (0=off)
#   KIT_GOAL_NO_HEURISTIC=0      -- set to 1 to skip fast-path and always use LLM classify
#   KIT_GOAL_SELFEVAL=0          -- set to 1 to enable the post-route self-evaluation verdict call
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"
GOAL="${1:?Usage: kit-goal '<goal>'}"
SESSION_DIR="$(kit_make_session_dir "goal")"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""
KIT_GOAL_CLASSIFY_TIMEOUT="${KIT_GOAL_CLASSIFY_TIMEOUT:-90}"
KIT_GOAL_NO_HEURISTIC="${KIT_GOAL_NO_HEURISTIC:-0}"
KIT_GOAL_SELFEVAL="${KIT_GOAL_SELFEVAL:-0}"

# Source kit config for KIT_ROOT (planted by install.ps1)
if [ -f "${SCRIPT_DIR}/kit-config.sh" ]; then
  # shellcheck source=kit-config.sh
  source "${SCRIPT_DIR}/kit-config.sh"
fi

kit_log_header "kit-goal" "goal" "$GOAL"

PWSH="$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || true)"
HOST_IS_WINDOWS=0
case "$(uname -s 2>/dev/null || echo unknown)" in
  MINGW*|MSYS*|CYGWIN*) HOST_IS_WINDOWS=1 ;;
esac

route_wrapper() {
  local base="${1:?wrapper base required}"
  shift
  if [ "$HOST_IS_WINDOWS" -eq 1 ] && [ -n "$PWSH" ] && [ -f "${SCRIPT_DIR}/${base}.ps1" ]; then
    kit_log "kit-goal: routing via PowerShell wrapper ${base}.ps1"
    "$PWSH" -NoProfile -File "${SCRIPT_DIR}/${base}.ps1" "$@"
  else
    kit_log "kit-goal: routing via Bash wrapper ${base}.sh"
    bash "${SCRIPT_DIR}/${base}.sh" "$@"
  fi
}

# Lifecycle: pre-session
if [ -n "$PWSH" ]; then
  "$PWSH" -NoProfile -File "$HOME/.agents/tools/pre-session.ps1" -Mode analyze -Task "$GOAL" 2>/dev/null || true
fi

# ---------------------------------------------------------------------------
# Heuristic fast-path classifier -- skips the LLM classify call for obvious goals.
# Sets GOAL_TYPE, INFO_CHECK, NEEDS_PLAN if confident; returns 0.
# Returns 1 if ambiguous (falls through to LLM classify).
# ---------------------------------------------------------------------------
kit_heuristic_classify() {
  local _gl _type="" _needs_plan="NO"
  _gl="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"

  # CODE/REFACTOR signals
  if printf '%s' "$_gl" | grep -qE '\b(implement|fix|add|build|write|create|update|change|modify|refactor|rename|delete|remove|move|extract|inline|patch)\b'; then
    _type="CODE"
  # INVESTIGATION signals
  elif printf '%s' "$_gl" | grep -qE '\b(investigate|debug|diagnose|root.cause|broken|failing|why is|what causes?|trace|crash|exception)\b'; then
    _type="INVESTIGATION"
  # ANALYSIS signals
  elif printf '%s' "$_gl" | grep -qE '\b(analyze|analyse|compare|evaluate|assess|survey|summarize|report.on)\b'; then
    _type="ANALYSIS"
  # REVIEW signals (only when no CODE intent present)
  elif printf '%s' "$_gl" | grep -qE '\b(review|inspect|audit)\b' && ! printf '%s' "$_gl" | grep -qE '\b(implement|fix|build|add)\b'; then
    _type="REVIEW"
  # BOOTSTRAP signals
  elif printf '%s' "$_gl" | grep -qE '\b(bootstrap|initialize|scaffold|init.repo|set.up.kit)\b'; then
    _type="BOOTSTRAP"
  # DESIGN signals
  elif printf '%s' "$_gl" | grep -qE '\b(redesign|restyle|visual.design|ui.design|ux.design|theme)\b'; then
    _type="DESIGN"
  fi

  [ -n "$_type" ] || return 1

  # Bump to NEEDS_PLAN=YES for CODE if goal looks cross-cutting
  if [ "$_type" = "CODE" ] && printf '%s' "$_gl" | grep -qE '\b(across|multiple.files|codebase|architecture|cross.cutting|end.to.end|e2e)\b'; then
    _needs_plan="YES"
  fi

  GOAL_TYPE="$_type"
  INFO_CHECK="SUFFICIENT"
  NEEDS_PLAN="$_needs_plan"
  return 0
}

# Phase 1: classify goal type
echo "kit-goal: Phase 1 -- classifying goal" >&2
CLASSIFY_OUT="$SESSION_DIR/classify.md"

GOAL_TYPE=""
INFO_CHECK=""
NEEDS_PLAN=""
_heuristic_ok=0

if [ "$KIT_GOAL_NO_HEURISTIC" != "1" ] && kit_heuristic_classify "$GOAL"; then
  _heuristic_ok=1
  echo "kit-goal: fast-path heuristic: type=$GOAL_TYPE needs_plan=$NEEDS_PLAN (skipped LLM classify)" >&2
  # Write synthetic classify.md so session artifacts are consistent
  printf 'INFO_CHECK: %s\nGOAL_TYPE: %s\nNEEDS_PLAN: %s\n# source: heuristic\n' \
    "$INFO_CHECK" "$GOAL_TYPE" "$NEEDS_PLAN" > "$CLASSIFY_OUT"
  kit_record_subagent "$SESSION_DIR" "copilot" "classify goal (heuristic)" "done"
else
  # LLM classify with wall-clock timeout to prevent indefinite stall
  echo "kit-goal: LLM classify (timeout=${KIT_GOAL_CLASSIFY_TIMEOUT}s)" >&2
  kit_announce_agent "copilot (classify)" "classify goal: $GOAL"
  kit_record_subagent "$SESSION_DIR" "copilot" "classify goal" "started"
  _c1=$(date +%s)
  _hb=$(kit_heartbeat_start)
  kit_copilot_timed "$KIT_GOAL_CLASSIFY_TIMEOUT" -p "Classify this goal. Output EXACTLY these lines (no extra text):
1. INFO_CHECK: <SUFFICIENT|NEEDED> (NEEDED only if you cannot define even one concrete success criterion)
2. GOAL_TYPE: <CODE|DESIGN|INVESTIGATION|ANALYSIS|REVIEW|REFACTOR|BOOTSTRAP|MULTI>
3. NEEDS_PLAN: <YES|NO> (YES only for CODE/REFACTOR when goal is an outcome-statement or touches cross-cutting concerns across >3 files; NO if goal is a clear concrete spec)
If INFO_CHECK is NEEDED, add:
4. INFO_QUESTION: <one compound question covering the most critical unknowns>
Goal: $GOAL" \
    $NOASK_FLAG | tee "$CLASSIFY_OUT" || true
  kit_heartbeat_stop "$_hb"
  kit_record_subagent "$SESSION_DIR" "copilot" "classify goal" "done"
  kit_done_agent "copilot (classify)" "$(($(date +%s) - _c1))"
fi

classifier_fail_closed() {
  local status="$1"
  local detail="$2"
  echo "kit-goal: $detail" >&2
  echo "GOAL_STATUS: $status | type: ${GOAL_TYPE:-unknown} | workflow: none | iterations: 0 | verdict: NEEDS_CLARIFICATION" | tee "$SESSION_DIR/goal.md"
  exit 1
}

GOAL_TYPE=""
if grep -q "GOAL_TYPE:" "$CLASSIFY_OUT" 2>/dev/null; then
  GOAL_TYPE=$(grep "GOAL_TYPE:" "$CLASSIFY_OUT" | head -1 | sed 's/.*GOAL_TYPE:[[:space:]]*//' | awk '{print $1}')
fi
echo "kit-goal: detected type=$GOAL_TYPE" >&2
case "$GOAL_TYPE" in
  CODE|DESIGN|INVESTIGATION|ANALYSIS|REVIEW|REFACTOR|BOOTSTRAP|MULTI)
    ;;
  "")
    classifier_fail_closed "UNROUTABLE" "classifier output missing GOAL_TYPE -- cannot route supported workflows"
    ;;
  *)
    classifier_fail_closed "UNROUTABLE" "classifier output has invalid GOAL_TYPE '$GOAL_TYPE' -- cannot route supported workflows"
    ;;
esac

# Extract info check result
INFO_CHECK=""
if grep -q "INFO_CHECK:" "$CLASSIFY_OUT" 2>/dev/null; then
  INFO_CHECK=$(grep "INFO_CHECK:" "$CLASSIFY_OUT" | head -1 | sed 's/.*INFO_CHECK:[[:space:]]*//' | awk '{print $1}')
fi
case "$INFO_CHECK" in
  SUFFICIENT|NEEDED)
    ;;
  "")
    classifier_fail_closed "NEEDS-CLARIFICATION" "classifier output missing INFO_CHECK -- cannot route supported workflows"
    ;;
  *)
    classifier_fail_closed "NEEDS-CLARIFICATION" "classifier output has invalid INFO_CHECK '$INFO_CHECK' -- cannot route supported workflows"
    ;;
esac

if [ "$INFO_CHECK" = "NEEDED" ]; then
  echo "kit-goal: goal is underspecified -- cannot proceed without clarification" >&2
  INFO_QUESTION=""
  if grep -q "INFO_QUESTION:" "$CLASSIFY_OUT" 2>/dev/null; then
    INFO_QUESTION=$(grep "INFO_QUESTION:" "$CLASSIFY_OUT" | head -1 | sed 's/.*INFO_QUESTION:[[:space:]]*//')
  fi
  [ -n "$INFO_QUESTION" ] || INFO_QUESTION="Please restate the goal with concrete success criteria, affected workflow(s), and intended verification."
  echo "GOAL_STATUS: NEEDS-CLARIFICATION | type: $GOAL_TYPE | workflow: none | iterations: 0 | verdict: NEEDS_CLARIFICATION"
  echo ""
  echo "Please provide more information before re-invoking kit-goal:"
  [ -n "$INFO_QUESTION" ] && echo "$INFO_QUESTION"
  exit 1
fi

NEEDS_PLAN=""
if grep -q "NEEDS_PLAN:" "$CLASSIFY_OUT" 2>/dev/null; then
  NEEDS_PLAN=$(grep "NEEDS_PLAN:" "$CLASSIFY_OUT" | head -1 | sed 's/.*NEEDS_PLAN:[[:space:]]*//' | awk '{print $1}')
fi
case "$NEEDS_PLAN" in
  YES|NO)
    ;;
  "")
    classifier_fail_closed "NEEDS-CLARIFICATION" "classifier output missing NEEDS_PLAN -- cannot route supported workflows"
    ;;
  *)
    classifier_fail_closed "NEEDS-CLARIFICATION" "classifier output has invalid NEEDS_PLAN '$NEEDS_PLAN' -- cannot route supported workflows"
    ;;
esac
echo "kit-goal: detected needs_plan=$NEEDS_PLAN" >&2

# Phase 2: route to the correct workflow wrapper or delegate the full loop
_route_exit=0
case "$GOAL_TYPE" in
  CODE|REFACTOR)
    if [ "$NEEDS_PLAN" = "YES" ]; then
      echo "kit-goal: CODE/REFACTOR with planning needed -- routing to kit-build.sh with planning prefix" >&2
      if route_wrapper "kit-build" "Plan before building: $GOAL" 2>&1 | tee "$SESSION_DIR/goal.md"; then
        :
      else
        _route_exit=$?
      fi
    else
      echo "kit-goal: routing CODE/REFACTOR direct -> kit-build.sh" >&2
      if route_wrapper "kit-build" "$GOAL" 2>&1 | tee "$SESSION_DIR/goal.md"; then
        :
      else
        _route_exit=$?
      fi
    fi
    ;;
  INVESTIGATION)
    echo "kit-goal: routing INVESTIGATION -> kit-investigate.sh" >&2
    if route_wrapper "kit-investigate" "$GOAL" 2>&1 | tee "$SESSION_DIR/goal.md"; then
      :
    else
      _route_exit=$?
    fi
    ;;
  ANALYSIS)
    echo "kit-goal: routing ANALYSIS -> kit-analyze.sh" >&2
    if route_wrapper "kit-analyze" "$GOAL" 2>&1 | tee "$SESSION_DIR/goal.md"; then
      :
    else
      _route_exit=$?
    fi
    ;;
  REVIEW)
    echo "kit-goal: routing REVIEW -> kit-review.sh" >&2
    if route_wrapper "kit-review" "$GOAL" 2>&1 | tee "$SESSION_DIR/goal.md"; then
      :
    else
      _route_exit=$?
    fi
    ;;
  BOOTSTRAP)
    echo "kit-goal: routing BOOTSTRAP -> kit-bootstrap.sh" >&2
    if route_wrapper "kit-bootstrap" "$(pwd)" 2>&1 | tee "$SESSION_DIR/goal.md"; then
      :
    else
      _route_exit=$?
    fi
    ;;
  DESIGN)
    echo "kit-goal: routing DESIGN -> kit-redesign.sh" >&2
    if route_wrapper "kit-redesign" "$GOAL" 2>&1 | tee "$SESSION_DIR/goal.md"; then
      :
    else
      _route_exit=$?
    fi
    ;;
  MULTI)
    echo "kit-goal: MULTI goal type -- cannot auto-route; please decompose into individual goals and re-invoke kit-goal for each" >&2
    echo "GOAL_STATUS: UNROUTABLE | type: MULTI | workflow: none | iterations: 0 | verdict: NEEDS_DECOMPOSITION" | tee "$SESSION_DIR/goal.md"
    echo "Tip: re-invoke kit-goal for each sub-goal (e.g., CODE aspects first, then REVIEW)." >&2
    _route_exit=1
    ;;
  ""|*)
    echo "kit-goal: unrecognized or empty goal type '${GOAL_TYPE:-}' -- cannot route; re-state the goal more specifically" >&2
    echo "GOAL_STATUS: UNROUTABLE | type: ${GOAL_TYPE:-empty} | workflow: none | iterations: 0 | verdict: NEEDS_CLARIFICATION" | tee "$SESSION_DIR/goal.md"
    echo "Supported types: CODE, DESIGN, INVESTIGATION, ANALYSIS, REVIEW, REFACTOR, BOOTSTRAP, MULTI" >&2
    _route_exit=1
    ;;
esac

# Phase: self-evaluation verdict -- disabled by default (overhead); enable with KIT_GOAL_SELFEVAL=1.
VERDICT_OUT="$SESSION_DIR/verdict.md"
if [ "${KIT_GOAL_SELFEVAL:-0}" = "1" ] && [ -f "$SESSION_DIR/goal.md" ] && ! grep -q "GOAL_VERDICT:" "$SESSION_DIR/goal.md" 2>/dev/null && [ "$_route_exit" -eq 0 ]; then
  echo "kit-goal: self-evaluation pass (KIT_GOAL_SELFEVAL=1)" >&2
  kit_announce_agent "copilot (verdict)" "self-evaluate goal verdict"
  kit_copilot_timed "$KIT_GOAL_CLASSIFY_TIMEOUT" -p "Self-evaluate the completed work against the original goal. Read the execution output at $SESSION_DIR/goal.md. Output EXACTLY: GOAL_VERDICT: <ON_TRACK|UNDER_DELIVERED|OFF_TRACK|NEEDS_REBUILD|NEEDS_CLARIFICATION> followed by a 2-sentence rationale and recommended next action. Original goal: $GOAL" \
    $NOASK_FLAG --allow-all-tools 2>/dev/null | tee "$VERDICT_OUT" || true
  if grep -q "GOAL_VERDICT:" "$VERDICT_OUT" 2>/dev/null; then
    echo "" >&2
    grep "GOAL_VERDICT:" "$VERDICT_OUT" | head -1 >&2
  fi
fi

# Lifecycle: post-session
SESSION_ID=$(basename "$SESSION_DIR")
if [ -n "$PWSH" ]; then
  "$PWSH" -NoProfile -File "$HOME/.agents/tools/post-session.ps1" -SessionId "$SESSION_ID" -NonInteractive -AutoApprove 2>/dev/null || true
fi

echo "kit-goal: report at $SESSION_DIR/goal.md" >&2
[ -f "$VERDICT_OUT" ] && echo "kit-goal: verdict at $VERDICT_OUT" >&2
[ "$_route_exit" -eq 0 ] || exit "$_route_exit"
