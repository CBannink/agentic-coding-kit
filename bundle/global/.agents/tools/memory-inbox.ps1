#!/usr/bin/env pwsh
# memory-inbox.ps1
# Manages the memory inbox -- collecting, reviewing, and committing learned patterns.
# Inspired by Gemini CLI's pattern: observations go into an inbox, the developer
# reviews and commits them explicitly. Transparent, version-controlled agent evolution.
#
# Usage:
#   pwsh ~/.agents/tools/memory-inbox.ps1 -Action collect -SessionId "abc123"
#   pwsh ~/.agents/tools/memory-inbox.ps1 -Action list
#   pwsh ~/.agents/tools/memory-inbox.ps1 -Action approve -EntryId "INBOX-001"
#   pwsh ~/.agents/tools/memory-inbox.ps1 -Action approve -EntryId "all"
#   pwsh ~/.agents/tools/memory-inbox.ps1 -Action reject -EntryId "INBOX-001"
#   pwsh ~/.agents/tools/memory-inbox.ps1 -Action flush
#   pwsh ~/.agents/tools/memory-inbox.ps1 -Action list -Json

param(
    [string]$RepoRoot = "",
    [ValidateSet("collect", "list", "approve", "reject", "flush")]
    [string]$Action = "list",
    [string]$SessionId = "",
    [string]$EntryId = "",
    [string]$Reason = "",
    [switch]$Json
)

. (Join-Path $PSScriptRoot "_paths.ps1")

$InboxPath   = Join-Path $HOME ".agents/context/memory-inbox.md"
$ContextDir  = Join-Path $HOME ".agents/context"
$GREEN  = "`e[92m"
$YELLOW = "`e[93m"
$RED    = "`e[91m"
$CYAN   = "`e[96m"
$RESET  = "`e[0m"
$BOLD   = "`e[1m"
$DIM    = "`e[2m"

if (-not $RepoRoot) { $RepoRoot = (Get-Location).Path }

# ── Helpers ────────────────────────────────────────────────────────────────────

function Ensure-InboxFile {
    if (-not (Test-Path $ContextDir)) {
        New-Item -ItemType Directory -Path $ContextDir -Force | Out-Null
    }
    if (-not (Test-Path $InboxPath)) {
        @"
# Memory Inbox

Patterns the agent learned during sessions. Review, approve, or reject each entry.
Approved entries are applied to their suggested target file.
Run: pwsh ~/.agents/tools/memory-inbox.ps1 -Action list

"@ | Set-Content -Path $InboxPath -Encoding utf8
    }
}

function Get-NextInboxId {
    if (-not (Test-Path $InboxPath)) { return "INBOX-001" }
    $content = Get-Content $InboxPath -Raw
    $ids = [regex]::Matches($content, 'INBOX-(\d+)') | ForEach-Object { [int]$_.Groups[1].Value }
    if ($ids.Count -eq 0) { return "INBOX-001" }
    $next = ($ids | Measure-Object -Maximum).Maximum + 1
    return "INBOX-{0:D3}" -f $next
}

function Parse-InboxEntries {
    if (-not (Test-Path $InboxPath)) { return @() }
    $content = Get-Content $InboxPath -Raw
    $entries = @()
    $blocks = [regex]::Split($content, '(?m)^---\s*$') | Where-Object { $_ -match '##\s+INBOX-' }
    foreach ($block in $blocks) {
        $idMatch      = [regex]::Match($block, '##\s+(INBOX-\d+)\s+\[(\w+)\]\s+\(([^)]+)\)')
        $sourceMatch  = [regex]::Match($block, 'Source:\s+(.+)')
        $patternMatch = [regex]::Match($block, 'Pattern:\s+(.+)')
        $targetMatch  = [regex]::Match($block, 'Suggested target:\s+(.+)')
        $reasonMatch  = [regex]::Match($block, 'Reason:\s+(.+)')
        $tsMatch      = [regex]::Match($block, 'Acted at:\s+(.+)')
        if (-not $idMatch.Success) { continue }
        $entries += [pscustomobject]@{
            Id      = $idMatch.Groups[1].Value
            Status  = $idMatch.Groups[2].Value
            Date    = $idMatch.Groups[3].Value
            Source  = if ($sourceMatch.Success)  { $sourceMatch.Groups[1].Value.Trim()  } else { "" }
            Pattern = if ($patternMatch.Success) { $patternMatch.Groups[1].Value.Trim() } else { "" }
            Target  = if ($targetMatch.Success)  { $targetMatch.Groups[1].Value.Trim()  } else { "" }
            Reason  = if ($reasonMatch.Success)  { $reasonMatch.Groups[1].Value.Trim()  } else { "" }
            ActedAt = if ($tsMatch.Success)      { $tsMatch.Groups[1].Value.Trim()      } else { "" }
            Raw     = $block
        }
    }
    return $entries
}

function Write-InboxEntry {
    param(
        [string]$Id,
        [string]$Status,
        [string]$Date,
        [string]$Source,
        [string]$Pattern,
        [string]$Target,
        [string]$Reason = "",
        [string]$ActedAt = ""
    )
    Ensure-InboxFile
    $entry = "## $Id [$Status] ($Date)`n"
    $entry += "Source: $Source`n"
    $entry += "Pattern: $Pattern`n"
    $entry += "Suggested target: $Target`n"
    if ($Reason)  { $entry += "Reason: $Reason`n" }
    if ($ActedAt) { $entry += "Acted at: $ActedAt`n" }
    $entry += "---`n"
    Add-Content -Path $InboxPath -Value "`n$entry" -Encoding utf8
}

function Update-EntryStatus {
    param([string]$Id, [string]$NewStatus, [string]$Reason = "", [string]$ActedAt = "")
    if (-not (Test-Path $InboxPath)) { return $false }
    $content = Get-Content $InboxPath -Raw

    # Match the header line for this entry
    $headerPattern = "(##\s+$([regex]::Escape($Id))\s+\[)\w+(\]\s+\([^)]+\))"
    if ($content -notmatch $headerPattern) { return $false }

    $content = [regex]::Replace($content, $headerPattern, "`${1}$NewStatus`$2")

    # Append Reason and ActedAt lines if not already present (insert after Target line)
    $targetLinePattern = "(?m)(Suggested target:\s+.+\n)"
    if ($Reason -and $content -notmatch "(?m)^Reason:") {
        # Only insert after the specific entry's target line (first occurrence after the ID)
        $idPos = $content.IndexOf("## $Id ")
        if ($idPos -ge 0) {
            $afterId = $content.Substring($idPos)
            $targetMatch = [regex]::Match($afterId, '(?m)(Suggested target:\s+.+\n)')
            if ($targetMatch.Success) {
                $insertPos = $idPos + $targetMatch.Index + $targetMatch.Length
                $insert = "Reason: $Reason`n"
                if ($ActedAt) { $insert += "Acted at: $ActedAt`n" }
                $content = $content.Substring(0, $insertPos) + $insert + $content.Substring($insertPos)
            }
        }
    } elseif ($ActedAt -and $content -notmatch "(?m)^Acted at:") {
        $idPos = $content.IndexOf("## $Id ")
        if ($idPos -ge 0) {
            $afterId = $content.Substring($idPos)
            $targetMatch = [regex]::Match($afterId, '(?m)(Suggested target:\s+.+\n)')
            if ($targetMatch.Success) {
                $insertPos = $idPos + $targetMatch.Index + $targetMatch.Length
                $content = $content.Substring(0, $insertPos) + "Acted at: $ActedAt`n" + $content.Substring($insertPos)
            }
        }
    }

    Set-Content -Path $InboxPath -Value $content -Encoding utf8
    return $true
}

function Apply-EntryToTarget {
    param([pscustomobject]$Entry)
    $target = $Entry.Target.Trim()
    # Expand ~ manually (PowerShell on some hosts doesn't expand it in paths)
    $target = $target -replace '^~', $HOME
    # If relative, root at RepoRoot
    if (-not [System.IO.Path]::IsPathRooted($target)) {
        $target = Join-Path $RepoRoot $target
    }
    if (-not (Test-Path $target)) {
        return $false, "Target file not found: $target"
    }
    $date = Get-Date -Format "yyyy-MM-dd"
    $line = "- [$date] [source:memory-inbox] [id:$($Entry.Id)] $($Entry.Pattern)"
    Add-Content -Path $target -Value "`n$line" -Encoding utf8
    return $true, $target
}

# ── ACTION: collect ────────────────────────────────────────────────────────────

function Invoke-Collect {
    Ensure-InboxFile

    $collected = 0
    $date = Get-Date -Format "yyyy-MM-dd"
    $globalReflectionsPath = Join-Path $HOME ".agents/context/reflections.md"

    # Source 1: reflections.md -- entries with count >= 2 (additive class)
    if (Test-Path $globalReflectionsPath) {
        $reflContent = Get-Content $globalReflectionsPath -Raw
        # Find entries with [class:additive] that appear 2+ times
        $reflLines = Get-Content $globalReflectionsPath
        $seen = @{}
        foreach ($line in $reflLines) {
            if ($line -match 'Pattern:\s+(.+)') {
                $pat = $Matches[1].Trim()
                if (-not $seen.ContainsKey($pat)) { $seen[$pat] = 0 }
                $seen[$pat]++
            }
        }
        foreach ($kv in $seen.GetEnumerator()) {
            if ($kv.Value -ge 2) {
                # Check if already in inbox (avoid duplicates)
                $existingContent = Get-Content $InboxPath -Raw
                if ($existingContent -notmatch [regex]::Escape($kv.Key.Substring(0, [Math]::Min(40, $kv.Key.Length)))) {
                    $id = Get-NextInboxId
                    Write-InboxEntry -Id $id -Status "pending" -Date $date `
                        -Source "reflections.md (seen $($kv.Value)x)" `
                        -Pattern $kv.Key `
                        -Target ".kit/context/memory.md"
                    $collected++
                }
            }
        }
    }

    # Source 2: prompt-improvements.md
    $promptImprovPath = Join-Path $HOME ".agents/context/prompt-improvements.md"
    if (Test-Path $promptImprovPath) {
        $piLines = Get-Content $promptImprovPath
        foreach ($line in $piLines) {
            if ($line -match '^\-\s+\[applied\]\s+(.+)') {
                $pat = $Matches[1].Trim()
                $existingContent = Get-Content $InboxPath -Raw
                if ($existingContent -notmatch [regex]::Escape($pat.Substring(0, [Math]::Min(40, $pat.Length)))) {
                    $id = Get-NextInboxId
                    Write-InboxEntry -Id $id -Status "pending" -Date $date `
                        -Source "prompt-improvements.md (applied)" `
                        -Pattern $pat `
                        -Target "~/.agents/instructions.md"
                    $collected++
                }
            }
        }
    }

    # Source 3: workflow-evidence.json from the session (repo-specific observations)
    if ($SessionId) {
        $evPath = Join-Path (Get-SessionDir $SessionId) "workflow-evidence.json"
        if (Test-Path $evPath) {
            try {
                $ev = Get-Content $evPath -Raw | ConvertFrom-Json
                # Observation: if verification_commands consistently mention slow tests
                if ($ev.verification_commands) {
                    foreach ($cmd in @($ev.verification_commands)) {
                        if ($cmd -match 'pytest|npm test|jest|cargo test') {
                            $repoName = Split-Path -Leaf $RepoRoot
                            $pat = "Repo '$repoName' uses '$cmd' for verification -- record in memory for pre-session context loading"
                            $existingContent = Get-Content $InboxPath -Raw
                            if ($existingContent -notmatch [regex]::Escape($repoName)) {
                                $id = Get-NextInboxId
                                Write-InboxEntry -Id $id -Status "pending" -Date $date `
                                    -Source "workflow-evidence.json (session:$SessionId, verification_commands)" `
                                    -Pattern $pat `
                                    -Target ".kit/context/memory.md"
                                $collected++
                                break  # one observation per session is enough
                            }
                        }
                    }
                }
                # Observation: agents_skipped patterns (systematic reviewer skipping)
                if ($ev.agents_skipped -and @($ev.agents_skipped).Count -ge 2) {
                    $skippedList = (@($ev.agents_skipped) | Select-Object -First 3) -join ', '
                    $pat = "Reviewers skipped in session ($skippedList) -- consider whether these are systematically skipped"
                    $existingContent = Get-Content $InboxPath -Raw
                    if ($existingContent -notmatch [regex]::Escape("Reviewers skipped in session")) {
                        $id = Get-NextInboxId
                        Write-InboxEntry -Id $id -Status "pending" -Date $date `
                            -Source "workflow-evidence.json (session:$SessionId, agents_skipped)" `
                            -Pattern $pat `
                            -Target ".kit/context/memory.md"
                        $collected++
                    }
                }
            } catch {}
        }

        # Source 4: auto-consolidate output (promoted patterns from this session)
        $autoConsolidateLog = Join-Path $HOME ".agents/context/auto-applied.md"
        if (Test-Path $autoConsolidateLog) {
            $autoLines = Get-Content $autoConsolidateLog
            foreach ($line in $autoLines) {
                if ($line -match '\[promoted\]\s+(.+)\s+-->\s+(.+)') {
                    $pat = $Matches[1].Trim()
                    $tgt = $Matches[2].Trim()
                    $existingContent = Get-Content $InboxPath -Raw
                    if ($existingContent -notmatch [regex]::Escape($pat.Substring(0, [Math]::Min(40, $pat.Length)))) {
                        $id = Get-NextInboxId
                        Write-InboxEntry -Id $id -Status "pending" -Date $date `
                            -Source "auto-applied.md (auto-promoted)" `
                            -Pattern $pat `
                            -Target $tgt
                        $collected++
                    }
                }
            }
        }
    }

    if ($Json) {
        [pscustomobject]@{ action = "collect"; collected = $collected; inbox = $InboxPath } | ConvertTo-Json -Compress
    } else {
        if ($collected -gt 0) {
            Write-Host "${GREEN}Memory inbox: $collected new pattern(s) collected.${RESET}"
            Write-Host "${DIM}Review with: pwsh ~/.agents/tools/memory-inbox.ps1 -Action list${RESET}"
        } else {
            Write-Host "${DIM}Memory inbox: no new patterns found.${RESET}"
        }
    }
}

# ── ACTION: list ──────────────────────────────────────────────────────────────

function Invoke-List {
    $entries = Parse-InboxEntries
    $pending  = @($entries | Where-Object { $_.Status -eq "pending" })
    $approved = @($entries | Where-Object { $_.Status -eq "approved" })
    $rejected = @($entries | Where-Object { $_.Status -eq "rejected" })

    if ($Json) {
        [pscustomobject]@{
            action   = "list"
            pending  = $pending.Count
            approved = $approved.Count
            rejected = $rejected.Count
            entries  = $entries
        } | ConvertTo-Json -Depth 5 -Compress
        return
    }

    Write-Host ""
    Write-Host "${BOLD}${CYAN}Memory Inbox${RESET}"
    Write-Host "${DIM}Pending: $($pending.Count)  Approved: $($approved.Count)  Rejected: $($rejected.Count)${RESET}"
    Write-Host ""

    if ($pending.Count -eq 0) {
        Write-Host "${DIM}No pending entries.${RESET}"
    } else {
        Write-Host "${BOLD}Pending entries:${RESET}"
        foreach ($e in $pending) {
            Write-Host ""
            Write-Host "  ${CYAN}$($e.Id)${RESET} (${DIM}$($e.Date)${RESET})"
            Write-Host "  Source:  ${DIM}$($e.Source)${RESET}"
            Write-Host "  Pattern: $($e.Pattern)"
            Write-Host "  Target:  ${DIM}$($e.Target)${RESET}"
        }
    }

    if ($approved.Count -gt 0) {
        Write-Host ""
        Write-Host "${BOLD}${DIM}Approved (recent):${RESET}"
        foreach ($e in ($approved | Select-Object -Last 5)) {
            Write-Host "  ${GREEN}$($e.Id)${RESET} ${DIM}$($e.Date) --> $($e.Target)${RESET}"
        }
    }

    if ($rejected.Count -gt 0) {
        Write-Host ""
        Write-Host "${BOLD}${DIM}Rejected (recent):${RESET}"
        foreach ($e in ($rejected | Select-Object -Last 5)) {
            $reasonSuffix = if ($e.Reason) { " (${DIM}$($e.Reason)${RESET})" } else { "" }
            Write-Host "  ${RED}$($e.Id)${RESET} ${DIM}$($e.Date)${RESET}$reasonSuffix"
        }
    }
    Write-Host ""
    Write-Host "${DIM}Approve: pwsh ~/.agents/tools/memory-inbox.ps1 -Action approve -EntryId <id>${RESET}"
    Write-Host "${DIM}Reject:  pwsh ~/.agents/tools/memory-inbox.ps1 -Action reject  -EntryId <id>${RESET}"
    Write-Host ""
}

# ── ACTION: approve ───────────────────────────────────────────────────────────

function Invoke-Approve {
    param([string]$Id)
    $entries = Parse-InboxEntries
    $now = Get-Date -Format "yyyy-MM-dd HH:mm"
    $results = @()

    if ($Id -eq "all") {
        $targets = @($entries | Where-Object { $_.Status -eq "pending" })
    } else {
        $targets = @($entries | Where-Object { $_.Id -eq $Id })
    }

    if ($targets.Count -eq 0) {
        if ($Json) {
            [pscustomobject]@{ action = "approve"; status = "not_found"; id = $Id } | ConvertTo-Json -Compress
        } else {
            Write-Host "${YELLOW}No pending entry found: $Id${RESET}"
        }
        return
    }

    foreach ($entry in $targets) {
        $ok, $detail = Apply-EntryToTarget -Entry $entry
        if ($ok) {
            Update-EntryStatus -Id $entry.Id -NewStatus "approved" -ActedAt $now | Out-Null
            $results += [pscustomobject]@{ id = $entry.Id; status = "approved"; target = $detail }
            if (-not $Json) {
                Write-Host "${GREEN}Approved $($entry.Id) --> $detail${RESET}"
            }
        } else {
            $results += [pscustomobject]@{ id = $entry.Id; status = "error"; detail = $detail }
            if (-not $Json) {
                Write-Host "${RED}Could not apply $($entry.Id): $detail${RESET}"
                Write-Host "${DIM}  Entry marked approved in inbox but could not write to target.${RESET}"
                Update-EntryStatus -Id $entry.Id -NewStatus "approved" -Reason "target-write-failed: $detail" -ActedAt $now | Out-Null
            }
        }
    }

    if ($Json) {
        [pscustomobject]@{ action = "approve"; results = $results } | ConvertTo-Json -Depth 4 -Compress
    }
}

# ── ACTION: reject ────────────────────────────────────────────────────────────

function Invoke-Reject {
    param([string]$Id, [string]$RejectReason)
    $entries = Parse-InboxEntries
    $now = Get-Date -Format "yyyy-MM-dd HH:mm"

    if ($Id -eq "all") {
        $targets = @($entries | Where-Object { $_.Status -eq "pending" })
    } else {
        $targets = @($entries | Where-Object { $_.Id -eq $Id })
    }

    if ($targets.Count -eq 0) {
        if ($Json) {
            [pscustomobject]@{ action = "reject"; status = "not_found"; id = $Id } | ConvertTo-Json -Compress
        } else {
            Write-Host "${YELLOW}No pending entry found: $Id${RESET}"
        }
        return
    }

    $results = @()
    foreach ($entry in $targets) {
        Update-EntryStatus -Id $entry.Id -NewStatus "rejected" -Reason $RejectReason -ActedAt $now | Out-Null
        $results += [pscustomobject]@{ id = $entry.Id; status = "rejected" }
        if (-not $Json) {
            $reasonSuffix = if ($RejectReason) { " (${DIM}$RejectReason${RESET})" } else { "" }
            Write-Host "${RED}Rejected $($entry.Id)${RESET}$reasonSuffix"
        }
    }

    if ($Json) {
        [pscustomobject]@{ action = "reject"; results = $results } | ConvertTo-Json -Depth 4 -Compress
    }
}

# ── ACTION: flush ─────────────────────────────────────────────────────────────

function Invoke-Flush {
    if (-not (Test-Path $InboxPath)) {
        if ($Json) {
            [pscustomobject]@{ action = "flush"; removed = 0 } | ConvertTo-Json -Compress
        } else {
            Write-Host "${DIM}Inbox file does not exist -- nothing to flush.${RESET}"
        }
        return
    }

    $entries = Parse-InboxEntries
    $cutoff  = (Get-Date).AddDays(-30)
    $toKeep  = @()
    $removed  = 0

    foreach ($e in $entries) {
        $isSettled = $e.Status -in @("approved", "rejected")
        $entryDate = $null
        $parsedOk  = [datetime]::TryParse($e.Date, [ref]$entryDate)
        if ($isSettled -and $parsedOk -and $entryDate -lt $cutoff) {
            $removed++
        } else {
            $toKeep += $e
        }
    }

    if ($removed -gt 0) {
        # Rebuild the inbox file from kept entries
        $header = @"
# Memory Inbox

Patterns the agent learned during sessions. Review, approve, or reject each entry.
Approved entries are applied to their suggested target file.
Run: pwsh ~/.agents/tools/memory-inbox.ps1 -Action list

"@
        $body = $toKeep | ForEach-Object {
            $block = "## $($_.Id) [$($_.Status)] ($($_.Date))`n"
            $block += "Source: $($_.Source)`n"
            $block += "Pattern: $($_.Pattern)`n"
            $block += "Suggested target: $($_.Target)`n"
            if ($_.Reason)  { $block += "Reason: $($_.Reason)`n" }
            if ($_.ActedAt) { $block += "Acted at: $($_.ActedAt)`n" }
            $block += "---"
            $block
        }
        Set-Content -Path $InboxPath -Value ($header + ($body -join "`n`n")) -Encoding utf8
    }

    if ($Json) {
        [pscustomobject]@{ action = "flush"; removed = $removed; kept = $toKeep.Count } | ConvertTo-Json -Compress
    } else {
        Write-Host "${GREEN}Flushed $removed settled entry/entries older than 30 days. Kept $($toKeep.Count).${RESET}"
    }
}

# ── Dispatch ──────────────────────────────────────────────────────────────────

switch ($Action) {
    "collect" { Invoke-Collect }
    "list"    { Invoke-List }
    "approve" { Invoke-Approve -Id $EntryId }
    "reject"  { Invoke-Reject  -Id $EntryId -RejectReason $Reason }
    "flush"   { Invoke-Flush }
}
