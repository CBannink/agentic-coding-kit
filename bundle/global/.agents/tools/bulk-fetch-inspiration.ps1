#!/usr/bin/env pwsh
# bulk-fetch-inspiration.ps1 -- pre-populate ~/.agents/inspiration/ with
# screenshots of first-party design system pages for ux-driver and ui-driver
# to reference during sessions.
#
# Sources are curated to first-party, public-readable, ToS-permissive design
# system docs only. Login-gated sites (Mobbin, Refero, SaaSFrame) are NOT
# fetched -- their ToS forbids scraping. Drivers reference those by URL only.
#
# Usage:
#   pwsh bulk-fetch-inspiration.ps1                    # fetch all, skip if <30 days old
#   pwsh bulk-fetch-inspiration.ps1 -Force             # refetch everything
#   pwsh bulk-fetch-inspiration.ps1 -MaxAgeDays 7      # refresh anything older than 7 days
#   pwsh bulk-fetch-inspiration.ps1 -Pattern dashboard # only fetch refs tagged 'dashboard'
#   pwsh bulk-fetch-inspiration.ps1 -List              # print catalog without fetching
#
# Output: PNGs at ~/.agents/inspiration/<slug>.png plus index.json describing
# what each shot is, when fetched, and which patterns it serves.
#
# This directory is gitignored at the kit level. It's local-only inspiration,
# never part of the redistributed bundle.

param(
    [switch]$Force,
    [int]$MaxAgeDays = 30,
    [string]$Pattern = "",
    [switch]$List,
    [int]$ConcurrentLimit = 1
)

# Resolve agents root
$AgentsRoot = if ($env:AGENTS_HOME) { $env:AGENTS_HOME } else { Join-Path $HOME ".agents" }
$InspirationDir = Join-Path $AgentsRoot "inspiration"
$IndexPath = Join-Path $InspirationDir "index.json"

New-Item -ItemType Directory -Path $InspirationDir -Force | Out-Null

# Curated catalog. Each entry:
#   slug:    filename + index key
#   url:     public, ToS-permissive
#   patterns: which patterns this informs (matches design-references.md sections)
#   note:    one-line on what to look at
$catalog = @(
    @{ slug = "material3-cards";        url = "https://m3.material.io/components/cards/overview";            patterns = @("dashboard","list");        note = "M3 card anatomy, elevation, spacing scale" }
    @{ slug = "material3-buttons";      url = "https://m3.material.io/components/buttons/overview";          patterns = @("form","detail");           note = "M3 button hierarchy and emphasis levels" }
    @{ slug = "material3-density";      url = "https://m3.material.io/foundations/layout/applying-layout/window-size-classes"; patterns = @("dashboard","list"); note = "M3 layout density / responsive scale" }
    @{ slug = "hig-layout";             url = "https://developer.apple.com/design/human-interface-guidelines/layout"; patterns = @("dashboard","detail"); note = "Apple HIG layout / safe areas / typography ramp" }
    @{ slug = "hig-buttons";            url = "https://developer.apple.com/design/human-interface-guidelines/buttons"; patterns = @("form","detail"); note = "Apple HIG button styles" }
    @{ slug = "radix-playground";       url = "https://www.radix-ui.com/themes/playground";                 patterns = @("dashboard","form","list");  note = "Radix component density / scales / 12-step color" }
    @{ slug = "radix-themes-overview";  url = "https://www.radix-ui.com/themes/docs/overview/getting-started"; patterns = @("dashboard");           note = "Radix Themes structural overview" }
    @{ slug = "shadcn-dashboard";       url = "https://ui.shadcn.com/examples/dashboard";                   patterns = @("dashboard");                note = "shadcn dashboard reference layout" }
    @{ slug = "shadcn-cards";           url = "https://ui.shadcn.com/examples/cards";                       patterns = @("dashboard","list");         note = "shadcn card variants" }
    @{ slug = "shadcn-forms";           url = "https://ui.shadcn.com/examples/forms";                       patterns = @("form","settings");          note = "shadcn form composition + validation patterns" }
    @{ slug = "shadcn-tasks";           url = "https://ui.shadcn.com/examples/tasks";                       patterns = @("list");                     note = "shadcn data table / list reference" }
    @{ slug = "geist-introduction";     url = "https://vercel.com/geist/introduction";                      patterns = @("dashboard","detail");       note = "Vercel Geist developer-tool aesthetic" }
    @{ slug = "linear-method";          url = "https://linear.app/method";                                  patterns = @("list","detail");            note = "Linear method principles / keyboard-first density" }
    @{ slug = "carbon-overview";        url = "https://carbondesignsystem.com/components/overview/components"; patterns = @("dashboard","list");      note = "IBM Carbon enterprise component set" }
    @{ slug = "carbon-empty-states";    url = "https://carbondesignsystem.com/patterns/empty-states-pattern/"; patterns = @("empty");                  note = "Carbon empty state patterns" }
    @{ slug = "atlassian-form";         url = "https://atlassian.design/components/form/examples";          patterns = @("form","settings");          note = "Atlassian form composition + validation" }
    @{ slug = "aria-apg-patterns";      url = "https://www.w3.org/WAI/ARIA/apg/patterns/";                  patterns = @("a11y");                     note = "WAI-ARIA Authoring Practices pattern index" }
)

if ($Pattern) {
    $catalog = @($catalog | Where-Object { $_.patterns -contains $Pattern })
    if ($catalog.Count -eq 0) {
        @{ ok = $false; error = "no entries match pattern '$Pattern'" } | ConvertTo-Json -Compress | Write-Output
        exit 1
    }
}

if ($List) {
    Write-Host "Inspiration catalog ($($catalog.Count) entries)"
    Write-Host "Cache dir: $InspirationDir"
    Write-Host ""
    foreach ($e in $catalog) {
        $existing = Join-Path $InspirationDir "$($e.slug).png"
        $status = if (Test-Path $existing) {
            $age = ((Get-Date) - (Get-Item $existing).LastWriteTime).Days
            "cached ${age}d"
        } else { "missing" }
        Write-Host ("  [{0,-12}] {1,-26} {2}" -f $status, $e.slug, $e.note)
    }
    exit 0
}

# Load existing index
$index = if (Test-Path $IndexPath) {
    try { Get-Content $IndexPath -Raw -Encoding UTF8 | ConvertFrom-Json -AsHashtable } catch { @{} }
} else { @{} }
if (-not $index) { $index = @{} }

# Python is required (playwright)
$python = if ($env:AGENTS_PYTHON) { $env:AGENTS_PYTHON } else { "python" }
if (-not (Get-Command $python -ErrorAction SilentlyContinue)) {
    Write-Host "Python not found at '$python'. Install python + playwright:"
    Write-Host "  python -m pip install playwright"
    Write-Host "  python -m playwright install chromium"
    exit 1
}

# Inline python -- multi-shot session, more efficient than spawning per URL.
# Reads jobs JSON from a file path passed as argv[1] (avoids PS5.1 stdin pipe quirks).
$pyScript = @'
import sys, json
from playwright.sync_api import sync_playwright

with open(sys.argv[1], "r", encoding="utf-8") as f:
    jobs = json.load(f)
results = []

with sync_playwright() as p:
    browser = p.chromium.launch(headless=True)
    ctx = browser.new_context(viewport={"width": 1440, "height": 900}, device_scale_factor=2)
    for job in jobs:
        url, out = job["url"], job["out"]
        page = ctx.new_page()
        try:
            try:
                page.goto(url, wait_until="networkidle", timeout=20000)
            except Exception:
                page.goto(url, wait_until="domcontentloaded", timeout=20000)
            for sel in [
                "button:has-text('Accept')", "button:has-text('Got it')",
                "button:has-text('I agree')", "button:has-text('Allow')",
                "[id*='cookie'] button", "[class*='cookie'] button"
            ]:
                try:
                    page.locator(sel).first.click(timeout=1500)
                    break
                except Exception:
                    continue
            page.wait_for_timeout(2500)
            page.screenshot(path=out, full_page=True)
            results.append({"slug": job["slug"], "ok": True})
        except Exception as e:
            results.append({"slug": job["slug"], "ok": False, "error": str(e)})
        finally:
            page.close()
    browser.close()

print(json.dumps(results))
'@

# Decide which entries need fetching
$jobs = @()
foreach ($e in $catalog) {
    $outFile = Join-Path $InspirationDir "$($e.slug).png"
    $needs = $true
    if (-not $Force -and (Test-Path $outFile)) {
        $age = ((Get-Date) - (Get-Item $outFile).LastWriteTime).Days
        if ($age -lt $MaxAgeDays) {
            $needs = $false
            Write-Host "  skip: $($e.slug) (cached ${age}d ago, < $MaxAgeDays)"
        }
    }
    if ($needs) {
        $jobs += @{ slug = $e.slug; url = $e.url; out = $outFile }
    }
}

if ($jobs.Count -eq 0) {
    Write-Host ""
    Write-Host "Nothing to fetch. Cache up to date."
    exit 0
}

Write-Host ""
Write-Host "Fetching $($jobs.Count) reference(s) into $InspirationDir..."

$tmpPy = New-TemporaryFile
$tmpJobs = New-TemporaryFile
[System.IO.File]::WriteAllText($tmpPy.FullName, $pyScript)
$payload = $jobs | ConvertTo-Json -Compress -Depth 5
[System.IO.File]::WriteAllText($tmpJobs.FullName, $payload)

try {
    $resultJson = & $python $tmpPy.FullName $tmpJobs.FullName 2>&1
    Remove-Item -Force $tmpPy.FullName -ErrorAction SilentlyContinue
    Remove-Item -Force $tmpJobs.FullName -ErrorAction SilentlyContinue
} catch {
    Remove-Item -Force $tmpPy.FullName -ErrorAction SilentlyContinue
    Remove-Item -Force $tmpJobs.FullName -ErrorAction SilentlyContinue
    Write-Host "ERROR: $($_.Exception.Message)"
    exit 1
}

# The python wrote a JSON line at the end; recover it
$lastLine = ($resultJson | Out-String).Trim().Split("`n") | Select-Object -Last 1
try {
    $results = $lastLine | ConvertFrom-Json
} catch {
    Write-Host "Could not parse python output. Raw output:"
    Write-Host ($resultJson | Out-String)
    exit 1
}

# Update index
$now = (Get-Date).ToString("o")
$success = 0
$fail = 0
foreach ($r in $results) {
    $catEntry = $catalog | Where-Object { $_.slug -eq $r.slug } | Select-Object -First 1
    if ($r.ok) {
        $index[$r.slug] = @{
            slug      = $r.slug
            url       = $catEntry.url
            patterns  = $catEntry.patterns
            note      = $catEntry.note
            fetched_at = $now
            file      = "$($r.slug).png"
        }
        $success++
        Write-Host "  OK:   $($r.slug)"
    } else {
        $fail++
        Write-Host "  FAIL: $($r.slug) -- $($r.error)"
    }
}

# Write index.json
$index | ConvertTo-Json -Depth 5 | Set-Content -Path $IndexPath -Encoding UTF8

Write-Host ""
Write-Host "Done. $success ok, $fail failed."
Write-Host "Cache: $InspirationDir"
Write-Host "Index: $IndexPath"

if ($fail -gt 0) { exit 1 } else { exit 0 }
