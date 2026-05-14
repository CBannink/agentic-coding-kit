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
kit_announce_agent "workflow-implementer" "Phase 1: git-archaeology + conventions detection for $REPO"
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "git-archaeology + conventions" "started"
_bs1=$(date +%s)
_hb=$(kit_heartbeat_start)
copilot --agent workflow-implementer \
    -p "You are bootstrapping $REPO for the agentic coding kit.

TASK: Run the git-archaeology workflow then detect workflow conventions, and write the combined output to $REPO/.kit/context/conventions.md.

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

echo "kit-bootstrap: Phase 1 done." >&2

# ------------------------------------------------------------------
# Phase 2 -- kit-init → .kit/context/{memory,handoffs,history,reflections}.md
# ------------------------------------------------------------------
echo "kit-bootstrap: Phase 2 -- kit-init..." >&2
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

Follow the skill's Hard Rules: evidence-grounded only, surgical writes, cite file:line for every memory.md entry, skip artifacts that don't apply." \
    $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/phase2-kit-init.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "kit-init" "done"
kit_done_agent "workflow-implementer (kit-init)" "$(($(date +%s) - _bs2))"

echo "kit-bootstrap: Phase 2 done." >&2

# ------------------------------------------------------------------
# Phase 3 -- wiki-init → .wiki/{index,architecture,codebase,features}.md + .features
# ------------------------------------------------------------------
echo "kit-bootstrap: Phase 3 -- wiki-init..." >&2
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

Follow the skill's Hard Rules: evidence-grounded only, cite the file for every claim, no generic templates." \
    $NOASK_FLAG --allow-all-tools | tee "$SESSION_DIR/phase3-wiki-init.md"
kit_heartbeat_stop "$_hb"
kit_record_subagent "$SESSION_DIR" "workflow-implementer" "wiki-init" "done"
kit_done_agent "workflow-implementer (wiki-init)" "$(($(date +%s) - _bs3))"

echo "kit-bootstrap: Phase 3 done." >&2

# ------------------------------------------------------------------
# Phase 4 -- convergence check
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
