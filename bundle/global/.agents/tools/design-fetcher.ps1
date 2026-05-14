#!/usr/bin/env pwsh
# design-fetcher.ps1 -- transient inspiration fetch for ux-driver and ui-driver.
# Opens a curated reference URL with Playwright and drops a screenshot into
# the session-state inspiration directory. Session-only -- never committed,
# never redistributed.
#
# Why: design-references.md links to public design sources (Material 3, HIG,
# Radix, etc.) and external inspiration sites (Mobbin, Refero, SaaSFrame).
# Drivers benefit from looking at the actual reference, not just reading
# about it. This tool fetches it for them, scoped to one session.
#
# Legal posture: this is the same as a browser cache. Screenshots land in
# the user's session-state directory (gitignored), are used for that session
# only, and are never embedded in repo memory or skill files. Equivalent
# to opening the URL in a browser tab while you work.
#
# Usage:
#   pwsh design-fetcher.ps1 -SessionId <id> -Url <url> [-Label <name>]
#   pwsh design-fetcher.ps1 -SessionId <id> -Pattern dashboard       # use design-references.md mapping
#
# Output:
#   { ok: true, path: "<screenshot path>", url: "<url>", label: "<label>" }

param(
    [Parameter(Mandatory=$true)][string]$SessionId,
    [string]$Url = "",
    [string]$Pattern = "",
    [string]$Label = "",
    [int]$ViewportWidth = 1440,
    [int]$ViewportHeight = 900,
    [int]$WaitMs = 2500
)

. (Join-Path $PSScriptRoot "_paths.ps1")
$inspirationDir = Join-Path (Get-SessionDir $SessionId) "inspiration"
New-Item -ItemType Directory -Path $inspirationDir -Force | Out-Null

# Pattern -> URL mapping (subset of design-references.md, first-party only by default)
$patternMap = @{
    "dashboard"     = "https://m3.material.io/components/cards/overview"
    "list"          = "https://www.radix-ui.com/themes/playground"
    "settings"      = "https://atlassian.design/components/form/examples"
    "form"          = "https://ui.shadcn.com/docs/components/form"
    "empty"         = "https://carbondesignsystem.com/patterns/empty-states-pattern/"
    "onboarding"    = "https://m3.material.io/foundations/getting-started"
}

if (-not $Url -and $Pattern) {
    if ($patternMap.ContainsKey($Pattern.ToLower())) {
        $Url = $patternMap[$Pattern.ToLower()]
        if (-not $Label) { $Label = "ref-$Pattern" }
    } else {
        @{
            ok = $false
            error = "unknown pattern '$Pattern'. Known: $($patternMap.Keys -join ', ')"
        } | ConvertTo-Json -Compress | Write-Output
        exit 1
    }
}

if (-not $Url) {
    @{ ok = $false; error = "must provide -Url or -Pattern" } | ConvertTo-Json -Compress | Write-Output
    exit 1
}

if (-not $Label) {
    $hostname = ([System.Uri]$Url).Host -replace '\.', '-'
    $Label = "ref-$hostname"
}

$python = if ($env:AGENTS_PYTHON) { $env:AGENTS_PYTHON } else { "python" }
$outFile = Join-Path $inspirationDir "$Label.png"

# Inline Python -- avoids shipping a separate .py file just for this
$pyScript = @"
import sys
from playwright.sync_api import sync_playwright

url = sys.argv[1]
out = sys.argv[2]
vw = int(sys.argv[3])
vh = int(sys.argv[4])
wait_ms = int(sys.argv[5])

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    ctx = browser.new_context(viewport={'width': vw, 'height': vh}, device_scale_factor=2)
    page = ctx.new_page()
    try:
        page.goto(url, wait_until='networkidle', timeout=20000)
    except Exception:
        page.goto(url, wait_until='domcontentloaded', timeout=20000)
    # Try to dismiss common cookie banners
    for sel in ["button:has-text('Accept')", "button:has-text('Got it')", "button:has-text('I agree')", "[id*='cookie'] button"]:
        try:
            page.locator(sel).first.click(timeout=1500)
            break
        except Exception:
            continue
    page.wait_for_timeout(wait_ms)
    page.screenshot(path=out, full_page=True)
    browser.close()
print('OK')
"@

$tmpPy = New-TemporaryFile
[System.IO.File]::WriteAllText($tmpPy.FullName, $pyScript)

try {
    $result = & $python $tmpPy.FullName $Url $outFile $ViewportWidth $ViewportHeight $WaitMs 2>&1
    Remove-Item -Force $tmpPy.FullName -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) {
        @{
            ok = $false
            error = "playwright fetch failed"
            detail = ($result -join "`n")
            url = $Url
        } | ConvertTo-Json -Compress | Write-Output
        exit 1
    }
} catch {
    Remove-Item -Force $tmpPy.FullName -ErrorAction SilentlyContinue
    @{
        ok = $false
        error = $_.Exception.Message
        url = $Url
    } | ConvertTo-Json -Compress | Write-Output
    exit 1
}

@{
    ok = $true
    path = $outFile
    url = $Url
    label = $Label
    note = "session-only screenshot. Not committed. Used by ux-driver/ui-driver during this session."
} | ConvertTo-Json -Compress | Write-Output
