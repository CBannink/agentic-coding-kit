#!/usr/bin/env bash

kit_resolve_session_root() {
    local repo_root="${1:-}"
    local force_repo_local="${2:-0}"

    if [ -n "${AGENTS_SESSION_ROOT:-}" ]; then
        printf '%s\n' "$AGENTS_SESSION_ROOT"
        return 0
    fi

    if [ -n "$repo_root" ] && { [ "$force_repo_local" = "1" ] || [ -d "$repo_root/.kit/context" ] || [ -d "$repo_root/.kit/workflows" ]; }; then
        printf '%s\n' "$repo_root/.kit/session-state"
        return 0
    fi

    local current
    current="${repo_root:-$(pwd)}"
    while [ -n "$current" ]; do
        if [ -d "$current/.kit/context" ] || [ -d "$current/.kit/workflows" ]; then
            printf '%s\n' "$current/.kit/session-state"
            return 0
        fi

        local parent
        parent="$(dirname "$current")"
        if [ "$parent" = "$current" ]; then
            break
        fi
        current="$parent"
    done

    printf '%s\n' "${HOME}/.agents/session-state"
}

kit_make_session_dir() {
    local label="${1:?session label required}"
    local repo_root="${2:-}"
    local force_repo_local="${3:-0}"
    local session_root
    session_root="$(kit_resolve_session_root "$repo_root" "$force_repo_local")"
    local session_dir="${session_root}/$(date +%Y%m%d-%H%M%S)-${label}"
    mkdir -p "$session_dir"
    printf '%s\n' "$session_dir"
}
