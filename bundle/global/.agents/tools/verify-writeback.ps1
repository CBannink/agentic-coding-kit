#!/usr/bin/env pwsh
# verify-writeback.ps1 -- the writeback enforcement gate.
#
# Why this exists: a markdown rule in CLAUDE.md saying "always update .wiki and
# memory" loses to behaviorally-trained ship-it instincts in a long-context
# session. The Iron Law catches "did tests pass" but not "did wiki/memory get
# updated." This tool catches the second class mechanically.
#
# Run it before claiming completion. It scans the session's git diff for
# user-visible changes (routes, components, public exports, env vars, schema
# migrations) and checks whether the appropriate doc-track files were touched
# in the same session. Emits a one-line summary the orchestrator MUST include
# in its final response to the user.
#
# Output shapes (always single-line JSON on stdout):
#   { ok=true,  status="ok",   summary="OK writeback: .wiki/features.md +3 lines" }
#   { ok=true,  status="warn", summary="WARN NO WRITEBACK -- user-visible feature added without docs update", ... }
#   { ok=false, error="..." }
#
# Enforcement modes (env var KIT_WRITEBACK_ENFORCE):
#   off    -- detector still runs, output is informational only
#   warn   -- (default) status="warn" surfaces in summary; exit 0
#   block  -- status="warn" exits non-zero so a wrapper can refuse to ship

param(
    [string]$SessionId = "",
    [string]$RepoRoot = "",
    [switch]$Json,
    [switch]$Quiet
)
if (-not $SessionId) { Write-Error "verify-writeback.ps1: -SessionId is required"; exit 1 }

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot "_paths.ps1")
$SessionId = Resolve-HookSessionId -Provided $SessionId

if (-not $RepoRoot) {
    $RepoRoot = (Get-Location).Path
}

$mode = if ($env:KIT_WRITEBACK_ENFORCE) { $env:KIT_WRITEBACK_ENFORCE.ToLower() } else { 'warn' }
if ($mode -notin @('off','warn','block')) { $mode = 'warn' }

# Resolve session dir and meta
$sessionDir = Get-SessionDir $SessionId
$metaPath = Join-Path $sessionDir "session-meta.json"
$baselinePath = Join-Path $sessionDir "baseline.json"

# ---------- gather changed files ----------
function Get-ChangedFiles {
    param([string]$Repo)
    Push-Location $Repo
    try {
        # Run git in a way that swallows stderr (git emits CRLF warnings on
        # Windows that PowerShell otherwise treats as command errors).
        $prevPref = $ErrorActionPreference
        $ErrorActionPreference = 'Continue'

        $null = & git rev-parse --is-inside-work-tree 2>&1
        if ($LASTEXITCODE -ne 0) { return @() }

        $baseSha = $null
        if (Test-Path $baselinePath) {
            try {
                $b = Get-Content -Raw $baselinePath | ConvertFrom-Json
                $baseSha = [string]$b.head_sha
            } catch {}
        }

        $diff = if ($baseSha) {
            & git diff --name-only $baseSha HEAD 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' }
        } else {
            # No session baseline: combine working-tree, staged, untracked, AND
            # the last 10 commits' files (covers "session committed multiple times").
            $a = & git diff --name-only HEAD 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' }
            $b = & git diff --name-only --cached 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' }
            $c = & git ls-files --others --exclude-standard 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' }
            # Last commit only (HEAD vs HEAD~1). For multi-commit sessions, the
            # session baseline is the right answer; without it we'd false-positive
            # on docs from much earlier commits.
            $d = & git diff --name-only HEAD~1..HEAD 2>&1 | Where-Object { $_ -is [string] -and $_ -notmatch '^warning:' -and $_ -notmatch '^fatal:' }
            @($a) + @($b) + @($c) + @($d)
        }
        $ErrorActionPreference = $prevPref
        return @($diff | Where-Object { $_ } | Select-Object -Unique)
    } finally { Pop-Location }
}

$files = Get-ChangedFiles -Repo $RepoRoot

# ---------- classification ----------
function Classify([string]$path) {
    $p = $path -replace '\\', '/'

    # Doc-track files (a writeback to one of these counts as "writeback happened")
    $docPatterns = @(
        '^\.wiki/.*\.md$',
        '^\.wiki/\.features$',
        '^\.kit/context/memory\.md$',
        '^\.kit/context/handoffs\.md$',
        '^\.kit/context/reflections\.md$',
        '^\.kit/context/agent-memory/.+\.md$',
        '^README\.md$',
        '^CHANGELOG\.md$',
        '^docs/.+\.md$'
    )
    foreach ($r in $docPatterns) { if ($p -match $r) { return 'doc' } }

    # User-visible categories that demand writeback
    if ($p -match '^src/(app|pages|routes|api)/.+\.(ts|tsx|js|jsx|py|go|rs)$') { return 'route' }
    if ($p -match '^src/.*components?/.+\.(tsx|jsx|vue|svelte)$')               { return 'component' }
    if ($p -match '^.*/(prisma|migrations?|schema)/.+\.(sql|prisma|py)$')        { return 'schema' }
    if ($p -match '(^|/)\.env(\..+)?$|/env\..+\.(ts|js|py)$')                    { return 'env' }
    if ($p -match '^src/.+/(public|index)\.(ts|js)$')                            { return 'export' }
    if ($p -match '^cli/|/bin/|^scripts/cli\.')                                  { return 'cli' }
    if ($p -match '^src/.+\.(ts|tsx|js|jsx|py|go|rs)$')                          { return 'code' }

    return 'other'
}

$buckets = @{ doc = @(); route = @(); component = @(); schema = @(); env = @(); export = @(); cli = @(); code = @(); other = @() }
foreach ($f in $files) {
    $buckets[(Classify $f)] += $f
}

# User-visible-change set (the categories that demand writeback)
$visibleCats = @('route','component','schema','env','export','cli')
$visibleFiles = @()
foreach ($c in $visibleCats) { $visibleFiles += $buckets[$c] }

# ---------- decide status ----------
$result = [ordered]@{
    ok                = $true
    status            = 'ok'
    summary           = ''
    user_visible_changes = $visibleFiles
    user_visible_count   = $visibleFiles.Count
    doc_files_touched    = $buckets['doc']
    doc_files_count      = $buckets['doc'].Count
    enforce_mode         = $mode
    warning              = $null
}

if ($visibleFiles.Count -eq 0) {
    # No user-visible changes -- writeback not required
    if ($buckets['doc'].Count -gt 0) {
        $result.summary = "OK writeback: $(($buckets['doc'] -join ', ')) (no user-visible changes; doc updates noted)"
    } else {
        $result.summary = "OK no writeback needed (no user-visible changes detected)"
    }
} elseif ($buckets['doc'].Count -gt 0) {
    # Both: user-visible changes AND docs touched. Good.
    $docSummary = ($buckets['doc'] | ForEach-Object { Split-Path $_ -Leaf }) -join ', '
    $result.summary = "OK writeback: $docSummary updated alongside $($visibleFiles.Count) user-visible file(s)"
} else {
    # User-visible changes present, no docs touched. Warn.
    $result.status = 'warn'
    $result.warning = "user-visible changes without docs update"
    $sample = ($visibleFiles | Select-Object -First 3) -join ', '
    if ($visibleFiles.Count -gt 3) { $sample += " (+$($visibleFiles.Count - 3) more)" }
    $result.summary = "WARN NO WRITEBACK -- $($visibleFiles.Count) user-visible file(s) changed [$sample] without touching .wiki/features.md, .kit/context/memory.md, or .kit/context/handoffs.md"
}

# ---------- emit + exit ----------
# Plain key-value output. PS5.1 has pathological parser binding issues with
# json builders in this script context, so we emit a simple grep-friendly
# format. Consumers parse it line-by-line.
$visibleFilesStr = ""
if ($visibleFiles.Count -gt 0) { $visibleFilesStr = $visibleFiles -join "|" }
$docFilesStr = ""
if ($buckets.doc.Count -gt 0) { $docFilesStr = $buckets.doc -join "|" }

Write-Output ("status=" + $result.status)
Write-Output ("summary=" + $result.summary)
Write-Output ("user_visible_count=" + $result.user_visible_count)
Write-Output ("doc_files_count=" + $result.doc_files_count)
Write-Output ("enforce_mode=" + $result.enforce_mode)
if ($visibleFilesStr) { Write-Output ("user_visible_changes=" + $visibleFilesStr) }
if ($docFilesStr)     { Write-Output ("doc_files_touched=" + $docFilesStr) }
if ($result.warning)  { Write-Output ("warning=" + $result.warning) }

# Block mode: non-zero exit when warn fires
if ($result.status -eq "warn" -and $mode -eq "block") { exit 2 }
exit 0
