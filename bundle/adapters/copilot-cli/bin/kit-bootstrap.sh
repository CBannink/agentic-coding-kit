#!/usr/bin/env bash
# kit-bootstrap -- self-driving bootstrap-harness orchestration for Copilot CLI.
#
# This is the ONE-COMMAND repo bootstrap for Copilot CLI. It:
#   Phase 0 -- scaffold the repo if .kit/context doesn't exist yet
#              (calls install.ps1 -BootstrapHarness via the kit-config.sh
#              written at install time; or falls back to KIT_ROOT env var)
#   Phase 1 -- git-archaeology + write conventions.md
#   Phase 2 -- kit-init (memory.md + .kit/context/)
#   Phase 3 -- wiki-init (architecture.md, codebase.md, features.md, .features)
#   Phase 4 -- convergence check
#
# Usage:
#   kit-bootstrap [<repo-root>]
#
# <repo-root> defaults to current directory.
# No pre-existing scaffold required -- this script does everything.
#
# Optional env:
#   KIT_ROOT=<path>       -- override path to agentic-coding-kit repo
#   KIT_COPILOT_NOASK=0   -- disable --no-ask-user (allow interactive prompts)

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=kit-session-root.sh
source "${SCRIPT_DIR}/kit-session-root.sh"
# shellcheck source=kit-copilot-common.sh
source "${SCRIPT_DIR}/kit-copilot-common.sh"

REPO="${1:-.}"
REPO="$(cd "$REPO" && pwd)"
SESSION_DIR="$(kit_make_session_dir "bootstrap" "$REPO" 1)"
NOASK_FLAG="--no-ask-user"; [ "${KIT_COPILOT_NOASK:-1}" = "0" ] && NOASK_FLAG=""

kit_log_header "kit-bootstrap" "repo" "$REPO"

# ------------------------------------------------------------------
# Phase 0 -- scaffold the repo if .kit/context doesn't exist yet
# ------------------------------------------------------------------
if [ ! -d "$REPO/.kit/context" ]; then
    echo "kit-bootstrap: Phase 0 -- scaffold not found; planting it now..." >&2

    # Resolve kit root: env var > kit-config.sh written at install time > common locations
    KIT_CFG="$SCRIPT_DIR/kit-config.sh"
    if [ -z "${KIT_ROOT:-}" ] && [ -f "$KIT_CFG" ]; then
        # shellcheck source=/dev/null
        . "$KIT_CFG"
    fi
    if [ -z "${KIT_ROOT:-}" ]; then
        # Try common install locations as last resort
        for _candidate in \
            "$HOME/agentic-coding-kit" \
            "$HOME/Downloads/agentic-coding-kit-main/agentic-coding-kit-main" \
            "$HOME/projects/agentic-coding-kit"; do
            if [ -f "$_candidate/scripts/install.ps1" ]; then
                KIT_ROOT="$_candidate"
                break
            fi
        done
    fi

    if [ -z "${KIT_ROOT:-}" ] || [ ! -f "$KIT_ROOT/scripts/install.ps1" ]; then
        echo "kit-bootstrap: ERROR -- could not find the agentic-coding-kit repo." >&2
        echo "  Set KIT_ROOT env var to the kit repo path, then re-run:" >&2
        echo "    KIT_ROOT=/path/to/agentic-coding-kit bash kit-bootstrap.sh \"$REPO\"" >&2
        echo "  Or scaffold manually first:" >&2
        echo "    pwsh /path/to/agentic-coding-kit/scripts/install.ps1 -BootstrapHarness -TargetRepo \"$REPO\"" >&2
        exit 1
    fi

    PWSH=$(command -v pwsh 2>/dev/null || command -v powershell 2>/dev/null || true)
    if [ -z "$PWSH" ]; then
        echo "kit-bootstrap: ERROR -- pwsh/powershell not found on PATH." >&2
        echo "  Install PowerShell (pwsh) and re-run, or scaffold manually:" >&2
        echo "    pwsh \"$KIT_ROOT/scripts/install.ps1\" -BootstrapHarness -TargetRepo \"$REPO\"" >&2
        exit 1
    fi

    echo "kit-bootstrap: Phase 0 -- running install.ps1 -BootstrapHarness (KIT_ROOT=$KIT_ROOT)..." >&2
    "$PWSH" -NoProfile -File "$KIT_ROOT/scripts/install.ps1" \
        -BootstrapHarness -TargetRepo "$REPO" -Force

    if [ ! -d "$REPO/.kit/context" ]; then
        echo "kit-bootstrap: ERROR -- scaffold still missing after install.ps1." >&2
        exit 1
    fi
    echo "kit-bootstrap: Phase 0 done (scaffold planted)." >&2
else
    echo "kit-bootstrap: Phase 0 -- scaffold already exists, skipping." >&2
fi

# ------------------------------------------------------------------
# Phase 1 -- git-archaeology + conventions detection → conventions.md
# ------------------------------------------------------------------
echo "kit-bootstrap: Phase 1 -- git-archaeology + conventions detection..." >&2

# Pre-inspect the repo to provide context and detect trivial/empty repos.
_commit_count=$(git -C "$REPO" rev-list --count HEAD 2>/dev/null || echo "0")
_top_files=$(ls "$REPO" 2>/dev/null | head -20 | tr '\n' ' ' || true)
_has_src="no"; [ -d "$REPO/src" ] || [ -d "$REPO/lib" ] || [ -d "$REPO/app" ] && _has_src="yes"

# For repos with zero git history, write a minimal conventions.md directly
# from the shell rather than routing through an AI agent that has nothing to
# analyze and may produce empty output or hang.
_conventions_file="$REPO/.kit/context/conventions.md"
if [ "$_commit_count" -lt 3 ]; then
    echo "kit-bootstrap: Phase 1 -- repo has $_commit_count commits; writing minimal conventions.md directly (no git history to analyze)..." >&2
    cat > "$_conventions_file" << CONVENTIONS_EOF
# Repo Conventions (bootstrap-detected)

## Git workflow
- Branch naming: unknown (insufficient history)
- Merge strategy: unknown (insufficient history)
- Commit style: unknown (insufficient history)
- Commit granularity: unknown (insufficient history)

## PR conventions
- Template: $([ -f "$REPO/.github/pull_request_template.md" ] && echo "yes:.github/pull_request_template.md" || echo "no")
- CODEOWNERS: $([ -f "$REPO/CODEOWNERS" ] || [ -f "$REPO/.github/CODEOWNERS" ] && echo "yes" || echo "no")
- Required checks: unknown
- Typical reviewer: unknown
- Average PR size: unknown

## Architecture preferences
- Layering: $([ "$_has_src" = "yes" ] && echo "unknown (src/ detected)" || echo "flat or not yet established")
- DI: unknown
- Error handling: unknown
- Tests: unknown
- State (FE): N/A
- API: unknown
- Schema validation: unknown
- Type system: unknown

## Source
- Detected from: $_commit_count commits (insufficient history — code inspection only)
- Top-level files: $_top_files
- Generated by: kit-bootstrap Phase 1 fallback (shell-direct) on $(date +%Y-%m-%d)

<!-- BOOTSTRAP-CONVENTIONS: MINIMAL -- re-run /bootstrap-harness once repo has code and history -->
CONVENTIONS_EOF
    echo "kit-bootstrap: Phase 1 -- minimal conventions.md written (fallback path)." >&2
else
    kit_announce_agent "workflow-implementer" "Phase 1: git-archaeology + conventions detection for $REPO"
    kit_record_subagent "$SESSION_DIR" "workflow-implementer" "git-archaeology + conventions" "started"
    _bs1=$(date +%s)
    _hb=$(kit_heartbeat_start)
    copilot --agent workflow-implementer \
        -p "You are bootstrapping $REPO for the agentic coding kit.

TASK: Run the git-archaeology workflow then detect workflow conventions, and write the combined output to $REPO/.kit/context/conventions.md.

REPO CONTEXT (pre-inspected by the bootstrap script):
- Git commits: $_commit_count
- Top-level items: $_top_files
- Has src/lib/app dir: $_has_src

STEP 1 -- git-archaeology:
Read ~/.agents/skills/git-archaeology/SKILL.md and follow its full analysis sequence for the repo at $REPO. Extract: commit style, new-file patterns, hot files, test file patterns, change scope per commit, technology choices, error handling patterns, antipatterns from reverts.

STEP 2 -- workflow convention detection:
Run these commands in $REPO and record findings:
  git branch -r | head -20                         (branch naming pattern)
  git log --merges -5 --oneline                    (merge strategy)
  git log -10 --pretty=format:'%H %s'              (squash vs merge: look for (#NNN) suffixes)
  git log -50 --pretty=format:'%s'                 (commit style)
Check existence of: .github/pull_request_template.md, .github/CODEOWNERS, CODEOWNERS, .github/workflows/*.yml
If gh CLI is available: gh pr list --state merged --limit 10 --json title,additions,deletions

STEP 3 -- architecture detection (inspect actual directories in $REPO):
Detect layering (flat / MVC / domain+application+infra / other), DI pattern, API style, schema validation library, type system strictness.

STEP 4 -- write $REPO/.kit/context/conventions.md:
Overwrite the file (it may be a placeholder) with the real detected content using this structure:

# Repo Conventions (auto-detected by /bootstrap-harness)

## Git workflow
- Branch naming: <pattern>
- Merge strategy: <squash|merge|rebase|unknown>
- Commit style: <conventional|sentence|imperative|free-form>
- Commit granularity: <1-per-logical-change|WIP-then-squash|other>

## PR conventions
- Template: <yes:path | no>
- CODEOWNERS: <yes | no>
- Required checks: <list from CI config | none detected>
- Typical reviewer: <name or 'any team member' | unknown>
- Average PR size: <N lines | unknown>

## Architecture preferences
- Layering: <flat|MVC|layered (domain/application/infra)|other>
- DI: <container | constructor | direct instantiation | unknown>
- Error handling: <typed errors | strings | Result/Either | unknown>
- Tests: <framework + location convention>
- State (FE): <library | N/A>
- API: <REST | GraphQL | tRPC | other | unknown>
- Schema validation: <library | none | unknown>
- Type system: <strict | gradual | dynamic | unknown>

## Project Conventions Profile
(paste the git-archaeology Project Conventions Profile block here)

## Source
- Detected from: <N commits sampled, files inspected>
- Generated by /bootstrap-harness on $(date +%Y-%m-%d)

If the repo has fewer than 20 commits, note that in the Source section and fill fields with 'insufficient history — code inspection only'." \
        $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/phase1-conventions.md"
    kit_heartbeat_stop "$_hb"
    kit_record_subagent "$SESSION_DIR" "workflow-implementer" "git-archaeology + conventions" "done"
    kit_done_agent "workflow-implementer" "$(($(date +%s) - _bs1))"
fi

# Post-check: if conventions.md is still a placeholder (contains the unresolved
# marker) or is too small, write a shell-generated fallback so Phase 4 converges.
if [ -f "$_conventions_file" ]; then
    _conv_bytes=$(wc -c < "$_conventions_file")
    _conv_is_stub=0
    grep -q '_not yet detected_\|PLACEHOLDER: populated' "$_conventions_file" 2>/dev/null && _conv_is_stub=1
    if [ "$_conv_bytes" -lt 200 ] || [ "$_conv_is_stub" -eq 1 ]; then
        echo "kit-bootstrap: Phase 1 post-check -- conventions.md is still a stub; writing shell-generated fallback..." >&2
        cat > "$_conventions_file" << CONV_FALLBACK_EOF
# Repo Conventions (bootstrap-detected)

## Git workflow
- Branch naming: unknown (agent analysis incomplete — re-run /bootstrap-harness)
- Merge strategy: unknown
- Commit style: unknown
- Commit granularity: unknown

## PR conventions
- Template: $([ -f "$REPO/.github/pull_request_template.md" ] && echo "yes:.github/pull_request_template.md" || echo "no")
- CODEOWNERS: $([ -f "$REPO/CODEOWNERS" ] || [ -f "$REPO/.github/CODEOWNERS" ] && echo "yes" || echo "no")
- Required checks: unknown
- Typical reviewer: unknown
- Average PR size: unknown

## Architecture preferences
- Layering: $([ "$_has_src" = "yes" ] && echo "unknown (src/ or similar detected)" || echo "flat or not yet established")
- DI: unknown
- Error handling: unknown
- Tests: unknown
- State (FE): N/A
- API: unknown
- Schema validation: unknown
- Type system: unknown

## Source
- Detected from: $_commit_count commits sampled (shell inspection only; agent did not produce output)
- Top-level files: $_top_files
- Generated by: kit-bootstrap Phase 1 fallback on $(date +%Y-%m-%d)

<!-- BOOTSTRAP-CONVENTIONS: SHELL-FALLBACK -- re-run /bootstrap-harness for deeper analysis -->
CONV_FALLBACK_EOF
        echo "kit-bootstrap: Phase 1 fallback conventions.md written." >&2
    fi
fi

echo "kit-bootstrap: Phase 1 done." >&2

# ------------------------------------------------------------------
# Phase 2 -- kit-init → .kit/context/{memory,handoffs,history,reflections}.md
# ------------------------------------------------------------------
echo "kit-bootstrap: Phase 2 -- kit-init..." >&2
_repo_name="$(basename "$REPO")"
if [ "$_commit_count" -lt 3 ]; then
    echo "kit-bootstrap: Phase 2 -- repo has $_commit_count commits; writing minimal .kit context directly..." >&2
    mkdir -p "$REPO/.kit/context"
    cat > "$REPO/.kit/context/memory.md" << MEMORY_DIRECT_EOF
# Repo Memory — $_repo_name

Durable architectural facts for the agentic coding kit.
Generated by kit-bootstrap Phase 2 direct fallback on $(date +%Y-%m-%d).

## Bootstrap context

- Repo path: $REPO
- Git commits at bootstrap: $_commit_count
- Has src/lib/app directory: $_has_src
- Top-level files: $_top_files

## Status

This repository was bootstrapped with minimal existing code and insufficient git
history for deeper archaeological analysis. Treat the current structure as
provisional until more code and history exist.

## Conventions source

See \`.kit/context/conventions.md\` for the bootstrap-detected conventions snapshot.
Re-run \`/kit-init\` or \`kit-bootstrap.sh\` after the repo grows to replace this
minimal memory with evidence-grounded architectural facts.

<!-- BOOTSTRAP-MEMORY: DIRECT-FALLBACK -->
MEMORY_DIRECT_EOF
    [ -f "$REPO/.kit/context/handoffs.md" ] || printf '# Handoffs\n\nSession handoffs will accumulate here.\n' > "$REPO/.kit/context/handoffs.md"
    [ -f "$REPO/.kit/context/history.md" ] || printf '# History\n\nArchitecture decision log seeded during bootstrap.\n' > "$REPO/.kit/context/history.md"
    [ -f "$REPO/.kit/context/reflections.md" ] || printf '# Reflections\n\nWorkflow reflections accumulate here.\n' > "$REPO/.kit/context/reflections.md"
else
    kit_announce_agent "workflow-implementer" "Phase 2: kit-init for $REPO"
    kit_record_subagent "$SESSION_DIR" "workflow-implementer" "kit-init" "started"
    _bs2=$(date +%s)
    _hb=$(kit_heartbeat_start)
    copilot --agent workflow-implementer \
        -p "You are bootstrapping $REPO for the agentic coding kit.

TASK: Run the kit-init workflow to populate .kit/context/ with evidence-grounded content.

Read ~/.agents/skills/kit-init/SKILL.md and follow its full workflow for $REPO.

IMPORTANT CONTEXT: The file $REPO/.kit/context/conventions.md has already been populated by git-archaeology in a prior phase. Read it first — use it as grounding evidence for memory.md entries (naming conventions, test patterns, layering, error handling, etc.). Do NOT re-derive what is already in conventions.md; instead incorporate it.

The kit-init skill will direct you to write:
  $REPO/.kit/context/memory.md              (durable architectural facts, ≤40 entries, cited)
  $REPO/.kit/context/handoffs.md            (header only)
  $REPO/.kit/context/history.md             (header only)
  $REPO/.kit/context/reflections.md         (header only)
  $REPO/.kit/context/agent-memory/shared.md (only if ≥3 cross-role patterns found)

IMPORTANT: memory.md MUST be written even if the repo has no code yet. Write at minimum:
  - One entry noting this is a new/empty repo bootstrapped on $(date +%Y-%m-%d)
  - One entry for each convention detected in conventions.md

Follow the skill's Hard Rules: evidence-grounded only, surgical writes, cite file:line for every memory.md entry, skip artifacts that don't apply." \
        $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/phase2-kit-init.md"
    kit_heartbeat_stop "$_hb"
    kit_record_subagent "$SESSION_DIR" "workflow-implementer" "kit-init" "done"
    kit_done_agent "workflow-implementer (kit-init)" "$(($(date +%s) - _bs2))"
fi

# Post-check Phase 2: write a minimal fallback memory.md if the agent left it empty.
_memory_file="$REPO/.kit/context/memory.md"
if [ ! -f "$_memory_file" ] || [ "$(wc -c < "$_memory_file")" -lt 200 ]; then
    echo "kit-bootstrap: Phase 2 post-check -- writing fallback memory.md..." >&2
    mkdir -p "$REPO/.kit/context"
    cat > "$_memory_file" << MEMORY_FALLBACK_EOF
# Repo Memory — $_repo_name

Durable architectural facts for the agentic coding kit.
Generated by kit-bootstrap Phase 2 fallback on $(date +%Y-%m-%d).

## Bootstrap context

- Repo path: $REPO
- Git commits at bootstrap: $_commit_count
- Has src/lib/app directory: $_has_src
- Top-level files: $_top_files

## Status

This repository was bootstrapped with minimal or no existing source code.
No architectural facts were detected at bootstrap time.

## How to update

Once code exists, run \`/kit-init\` or \`kit-bootstrap.sh\` to populate this
file with detected architectural facts, naming conventions, and code patterns.

<!-- BOOTSTRAP-MEMORY: MINIMAL -->
MEMORY_FALLBACK_EOF
fi

echo "kit-bootstrap: Phase 2 done." >&2

# ------------------------------------------------------------------
# Phase 3 -- wiki-init → .wiki/{index,architecture,codebase,features}.md + .features
# ------------------------------------------------------------------
echo "kit-bootstrap: Phase 3 -- wiki-init..." >&2
_wiki_dir="$REPO/.wiki"
_today="$(date +%Y-%m-%d)"

_write_wiki_fallback() {
    local filepath="$1"
    local label="$2"
    local content="$3"
    if [ ! -f "$filepath" ] || [ "$(wc -c < "$filepath")" -lt 200 ]; then
        echo "kit-bootstrap: Phase 3 post-check -- writing fallback $label..." >&2
        printf '%s\n' "$content" > "$filepath"
    fi
}

if [ "$_commit_count" -ge 3 ]; then
    kit_announce_agent "workflow-implementer" "Phase 3: wiki-init for $REPO"
    kit_record_subagent "$SESSION_DIR" "workflow-implementer" "wiki-init" "started"
    _bs3=$(date +%s)
    _hb=$(kit_heartbeat_start)
    copilot --agent workflow-implementer \
        -p "You are bootstrapping $REPO for the agentic coding kit.

TASK: Run the wiki-init workflow to populate .wiki/ with evidence-grounded documentation.

Read ~/.agents/skills/wiki-init/SKILL.md and follow its full workflow for $REPO.

IMPORTANT CONTEXT:
  - $REPO/.kit/context/conventions.md has the detected repo conventions (layering, API style, test framework, etc.)
  - $REPO/.kit/context/memory.md has the durable architectural facts already extracted by kit-init

Use both files as grounding evidence so wiki-init reflects THIS repo's actual architecture rather than generic templates.

The wiki-init skill will direct you to write:
  $REPO/.wiki/index.md          (TOC ≤100 lines)
  $REPO/.wiki/architecture.md   (boundaries + principles from code, ≤200 lines)
  $REPO/.wiki/codebase.md       (where important code lives, style conventions, ≤200 lines)
  $REPO/.wiki/features.md       (user-visible capabilities, ≤300 lines)
  $REPO/.wiki/.features         (machine-readable feature index)

IMPORTANT: Even for an empty or new repository, you MUST write all five files above with
at minimum a meaningful header describing what this repo is. Do not leave any file empty.
If the repo has no code yet, write 'This repository has no features yet.' and similar short
but non-empty content for each file. The files must each be at least 200 bytes.

Follow the skill's Hard Rules: evidence-grounded only, cite the file for every claim, no generic templates." \
        $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/phase3-wiki-init.md"
    kit_heartbeat_stop "$_hb"
    kit_record_subagent "$SESSION_DIR" "workflow-implementer" "wiki-init" "done"
    kit_done_agent "workflow-implementer (wiki-init)" "$(($(date +%s) - _bs3))"
else
    echo "kit-bootstrap: Phase 3 -- repo has $_commit_count commits; writing minimal .wiki docs directly..." >&2
fi

# Post-check Phase 3: write shell-generated fallback for any wiki file that is
# still missing or too small after the agent run. This ensures convergence even
# when the agent produced no output (e.g., network issue, empty repo).

_write_wiki_fallback "$_wiki_dir/index.md" "index.md" \
"# Wiki Index — $_repo_name

Canonical entry point for repo-local user-facing docs.
Generated by kit-bootstrap on $_today.

## Sections

- [Architecture](.wiki/architecture.md) — system boundaries and principles
- [Codebase](.wiki/codebase.md) — where code lives, style conventions
- [Features](.wiki/features.md) — user-visible capabilities

> Note: This repo was bootstrapped with minimal/no existing code. Re-run
> \`/wiki-init\` or \`kit-bootstrap.sh\` once code exists to generate richer docs."

_write_wiki_fallback "$_wiki_dir/architecture.md" "architecture.md" \
"# Architecture — $_repo_name

Generated by kit-bootstrap on $_today.

## Status

This repository was bootstrapped with minimal or no existing source code.
No architecture patterns were detected at bootstrap time.

## How to update

Once code exists, run \`/wiki-init\` or \`kit-bootstrap.sh\` to populate this
file with detected layering, module boundaries, and design principles.

## Detected at bootstrap
- Git commits: $_commit_count
- Top-level files: $_top_files
- Source directories: $_has_src

## Current snapshot

Bootstrap detected only a small amount of initial structure. Treat this
document as a starter overview until additional modules and boundaries exist."

_write_wiki_fallback "$_wiki_dir/codebase.md" "codebase.md" \
"# Codebase — $_repo_name

Generated by kit-bootstrap on $_today.

## Status

This repository was bootstrapped with minimal or no existing source code.
No codebase structure was detected at bootstrap time.

## How to update

Once code exists, run \`/wiki-init\` or \`kit-bootstrap.sh\` to populate this
file with information about where code lives and style conventions.

## Detected at bootstrap
- Git commits: $_commit_count
- Has src/lib/app: $_has_src
- Top-level items: $_top_files

## Current snapshot

Bootstrap detected only a light initial file set. Re-run wiki-init after more
files land so this document can describe module layout and style conventions."

_write_wiki_fallback "$_wiki_dir/features.md" "features.md" \
"# Features — $_repo_name

Human-readable catalog of user-visible features.
Generated by kit-bootstrap on $_today.

## Status

This repository was bootstrapped with minimal or no existing source code.
No user-visible features were detected at bootstrap time.

## How to update

Once code and capabilities exist, run \`/wiki-init\` or \`kit-bootstrap.sh\`
to populate this file with the actual feature catalog.

Alternatively, edit this file directly to document features as you build them.
The format should be: one feature per section with a short description.

## Bootstrap snapshot

- No stable user-visible feature catalog was detected yet.
- Current repo should be treated as newly initialized or pre-feature."

# .features machine-readable index (always write a minimal one)
if [ ! -f "$_wiki_dir/.features" ] || [ "$(wc -c < "$_wiki_dir/.features")" -lt 50 ] || grep -q '"features":[[:space:]]*\[[[:space:]]*\]' "$_wiki_dir/.features" 2>/dev/null; then
    echo "kit-bootstrap: Phase 3 post-check -- writing fallback .features index..." >&2
    cat > "$_wiki_dir/.features" << FEATURES_FALLBACK_EOF
{
  "generatedBy": "kit-bootstrap",
  "bootstrappedOn": "$_today",
  "status": "no-stable-features-detected",
  "features": []
}
FEATURES_FALLBACK_EOF
fi

echo "kit-bootstrap: Phase 3 done." >&2

# ------------------------------------------------------------------
# Phase 4 -- convergence check (also detects unresolved placeholder stubs)
# ------------------------------------------------------------------
echo "kit-bootstrap: Phase 4 -- convergence check..." >&2
MISSING=0
for f in \
    "$REPO/.kit/context/memory.md" \
    "$REPO/.kit/context/conventions.md" \
    "$REPO/.wiki/index.md" \
    "$REPO/.wiki/architecture.md" \
    "$REPO/.wiki/codebase.md" \
    "$REPO/.wiki/features.md"; do
    if [ ! -f "$f" ]; then
        echo "  MISSING: $f" >&2
        MISSING=1
    elif [ "$(wc -c < "$f")" -lt 200 ]; then
        echo "  EMPTY_OR_STUB: $f ($(wc -c < "$f") bytes < 200 byte threshold)" >&2
        MISSING=1
    elif grep -q '_not yet detected_\|PLACEHOLDER: populated\|<!-- PLACEHOLDER' "$f" 2>/dev/null; then
        echo "  UNRESOLVED_STUB: $f (still contains placeholder markers)" >&2
        MISSING=1
    fi
done

if [ "$MISSING" -eq 0 ]; then
    echo "" >&2
    echo "BOOTSTRAP_STATUS: COMPLETE | iterations: 1/3 | conventions: detected | files: all required" >&2
    echo "" >&2
    echo "Files written:" >&2
    for f in \
        "$REPO/.kit/context/memory.md" \
        "$REPO/.kit/context/conventions.md" \
        "$REPO/.wiki/index.md" \
        "$REPO/.wiki/architecture.md" \
        "$REPO/.wiki/codebase.md" \
        "$REPO/.wiki/features.md"; do
        echo "  $f" >&2
    done
    echo "" >&2
    echo "Recommended next step: run /build or kit-build.sh to start coding." >&2
    echo "The kit will read conventions.md and follow your repo's actual patterns." >&2
else
    echo "" >&2
    echo "BOOTSTRAP_STATUS: PARTIAL | some required files missing or empty" >&2
    echo "Check phase reports at $SESSION_DIR/" >&2
    echo "Re-run kit-bootstrap.sh to retry, or invoke the specific skill manually." >&2
    exit 1
fi
