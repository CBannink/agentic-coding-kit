#!/usr/bin/env bash

kit_now() {
    date '+%Y-%m-%d %H:%M:%S'
}

kit_log() {
    local line
    line="$(kit_now) $*"
    printf '%s\n' "$line" >&2
    if [ -n "${SESSION_DIR:-}" ]; then
        mkdir -p "$SESSION_DIR"
        printf '%s\n' "$line" >> "$SESSION_DIR/progress.log"
    fi
}

kit_resolve_copilot_cli() {
    if [ -n "${KIT_COPILOT_COMMAND_KIND:-}" ]; then
        return 0
    fi

    if type -P copilot >/dev/null 2>&1; then
        KIT_COPILOT_COMMAND_KIND="copilot"
        KIT_COPILOT_COMMAND_LABEL="copilot"
        return 0
    fi

    if type -P gh >/dev/null 2>&1 && command gh copilot --help >/dev/null 2>&1; then
        KIT_COPILOT_COMMAND_KIND="gh"
        KIT_COPILOT_COMMAND_LABEL="gh copilot"
        return 0
    fi

    kit_log "ERROR -- GitHub Copilot CLI not found. Install the standalone 'copilot' binary or 'gh' with Copilot enabled."
    return 127
}

kit_run_copilot() {
    kit_resolve_copilot_cli || return $?

    if [ "$KIT_COPILOT_COMMAND_KIND" = "gh" ]; then
        command gh copilot "$@"
        return $?
    fi

    command copilot "$@"
}

copilot() {
    kit_run_copilot "$@"
}

kit_log_header() {
    local script_name="${1:?script name required}"
    local topic_label="${2:-goal}"
    local topic_value="${3:-}"

    kit_resolve_copilot_cli || return $?
    kit_log "$script_name: session=$SESSION_DIR"
    kit_log "$script_name: cli=$KIT_COPILOT_COMMAND_LABEL"
    kit_log "$script_name: $topic_label=$topic_value"
}

kit_session_id_from_dir() {
    local session_dir="${1:-${SESSION_DIR:-}}"
    if [ -z "$session_dir" ]; then
        return 1
    fi

    basename "$session_dir"
}

kit_warn_ps_runner_unavailable() {
    local runner="${1:-${AGENTS_HOME:-$HOME/.agents}/tools/_run-ps.sh}"
    if [ "${KIT_PS_RUNNER_WARNED:-0}" = "1" ]; then
        return 0
    fi

    KIT_PS_RUNNER_WARNED=1
    export KIT_PS_RUNNER_WARNED
    kit_log "WARN -- PowerShell durable recording unavailable: $runner missing or not executable; continuing without workflow/state evidence."
}

kit_run_ps_tool() {
    local script_path="${1:?script path required}"
    shift

    local runner="${AGENTS_HOME:-$HOME/.agents}/tools/_run-ps.sh"
    if [ ! -x "$runner" ]; then
        kit_warn_ps_runner_unavailable "$runner"
        return 1
    fi

    "$runner" "$script_path" "$@" >/dev/null 2>&1
}

kit_announce_agent() {
    local agent="${1:?agent label required}"
    local task="${2:-working}"

    KIT_ACTIVE_AGENT_LABEL="$agent"
    KIT_ACTIVE_AGENT_TASK="$task"
    printf '\n' >&2
    printf '══════════════════════════════════════════════════════════════\n' >&2
    printf '  ▶ Agent:   %s\n' "$agent" >&2
    printf '  ▶ Working: %s\n' "$task" >&2
    printf '  ▶ Started: %s\n' "$(date '+%H:%M:%S')" >&2
    printf '══════════════════════════════════════════════════════════════\n' >&2
    kit_log "spawned agent=$agent"
    kit_log "working[$agent]=$task"
}

kit_record_subagent() {
    local session_dir="${1:?session dir required}"
    local agent="${2:?agent required}"
    local task="${3:-}"
    local status="${4:-unknown}"
    local session_id
    local agents_root="${AGENTS_HOME:-$HOME/.agents}"
    local workflow_tool="$agents_root/tools/workflow-evidence.ps1"
    local state_gate_tool="$agents_root/tools/state-gate.ps1"

    mkdir -p "$session_dir"
    printf '%s\t%s\t%s\t%s\n' "$(kit_now)" "$agent" "$status" "$task" >> "$session_dir/agent-status.tsv"

    session_id="$(kit_session_id_from_dir "$session_dir")" || return 0

    if [ -f "$workflow_tool" ]; then
        if [ "$status" = "started" ]; then
            kit_run_ps_tool "$workflow_tool" -SessionId "$session_id" -AddAgent "$agent|$task" || true
        fi
        kit_run_ps_tool "$workflow_tool" -SessionId "$session_id" -AddNote "subagent:$status|$agent|$task" || true
    fi

    if [ "$status" = "started" ] && [ -f "$session_dir/state.json" ] && [ -f "$state_gate_tool" ]; then
        kit_run_ps_tool "$state_gate_tool" -SessionId "$session_id" -AddAgent "$agent" || true
    fi
}

# Detect a timeout command (GNU timeout on Linux/Git-Bash; gtimeout on macOS/Homebrew).
kit_timeout_cmd() {
    if command -v timeout >/dev/null 2>&1; then
        printf '%s' "timeout"; return 0
    fi
    if command -v gtimeout >/dev/null 2>&1; then
        printf '%s' "gtimeout"; return 0
    fi
    return 1
}

# Run copilot with an optional wall-clock timeout.
# Usage: kit_copilot_timed <seconds> [copilot args...]
# <seconds> == 0 means no timeout.
# Exit 124 on timeout (same as GNU timeout convention).
# Handles both 'copilot' binary mode and 'gh copilot' mode correctly.
kit_copilot_timed() {
    local t="${1:?timeout_seconds required}"; shift
    local _tcmd
    kit_resolve_copilot_cli || return $?
    if [ "${t}" -gt 0 ] 2>/dev/null && _tcmd="$(kit_timeout_cmd 2>/dev/null)"; then
        if [ "${KIT_COPILOT_COMMAND_KIND:-}" = "gh" ]; then
            "$_tcmd" "$t" gh copilot "$@"
        else
            "$_tcmd" "$t" copilot "$@"
        fi
    else
        kit_run_copilot "$@"
    fi
}

# Return 0 (true) if the goal looks trivially scoped (single file or short).
# Trivial goals skip the workflow-explorer phase.
kit_is_trivial_goal() {
    local goal="$1"
    # Explicit file reference (e.g. src/math_utils.py, lib/utils.ts)
    if printf '%s' "$goal" | grep -qE '\.[a-zA-Z]{2,5}([[:space:]]|$|/)'; then
        return 0
    fi
    # Very short goals (under 12 words) are trivially scoped
    local wc
    wc=$(printf '%s' "$goal" | wc -w)
    if [ "$wc" -lt 12 ]; then
        return 0
    fi
    return 1
}

kit_heartbeat_start() {
    local agent="${KIT_ACTIVE_AGENT_LABEL:-session}"
    local task="${KIT_ACTIVE_AGENT_TASK:-running}"
    local interval="${KIT_COPILOT_HEARTBEAT_SEC:-20}"

    (
        while true; do
            sleep "$interval"
            kit_log "still-running[$agent]=$task"
        done
    ) &
    printf '%s\n' "$!"
}

kit_heartbeat_stop() {
    local pid="${1:-}"
    if [ -z "$pid" ]; then
        return 0
    fi

    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

kit_done_agent() {
    local agent="${1:?agent label required}"
    local duration="${2:-0}"

    kit_log "completed agent=$agent duration=${duration}s"
}
