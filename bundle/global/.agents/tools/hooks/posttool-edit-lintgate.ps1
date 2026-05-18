#!/usr/bin/env pwsh
# posttool-edit-lintgate.ps1 -- PostToolUse hook for Edit/Write tools.
#
# Implements SWE-Agent's lint-gated editing pattern: after every file edit,
# run a language-appropriate linter. If linting fails, warn the agent to fix
# the syntax error before proceeding.
#
# Fires on: Edit, Write, NotebookEdit
#
# Behavior:
#   1. Extract the edited file path from tool_input.
#   2. Map the file extension to a fast syntax-only linter command.
#   3. If no linter is installed or extension is unknown, exit 0 silently.
#   4. Run the linter with a 10-second timeout.
#   5. On failure, emit a warning message to stderr and exit 0 (warn, not block).
#
# Design constraints:
#   - Never installs anything -- only uses linters already on PATH.
#   - Skips silently when a linter is not found.
#   - Target: < 2s wall time for common cases (py_compile, PSParser, JSON).
#
# Opt-out: KIT_DISABLED_HOOKS=edit-lintgate

$ErrorActionPreference = "Continue"
. (Join-Path $PSScriptRoot "../_paths.ps1") -ErrorAction SilentlyContinue

$disabledHooks = if ($env:KIT_DISABLED_HOOKS) { @($env:KIT_DISABLED_HOOKS -split ',') } else { @() }
if ($disabledHooks -contains "edit-lintgate") { exit 0 }

# --- Parse stdin payload ---
$rawInput = [Console]::In.ReadToEnd()
if (-not $rawInput) { exit 0 }
try {
    $payload = $rawInput | ConvertFrom-Json
} catch { exit 0 }

# --- Only act on edit-class tool calls ---
$toolName = [string]$payload.tool_name
if ($toolName -notin @("Edit", "Write", "NotebookEdit", "str_replace_editor", "file_editor")) { exit 0 }

# --- Resolve file path from tool_input ---
$filePath = $null
if ($payload.tool_input.file_path)   { $filePath = [string]$payload.tool_input.file_path }
elseif ($payload.tool_input.path)    { $filePath = [string]$payload.tool_input.path }
elseif ($payload.tool_input.filePath){ $filePath = [string]$payload.tool_input.filePath }

if (-not $filePath) { exit 0 }

# Resolve relative paths using cwd from payload when available
if (-not [System.IO.Path]::IsPathRooted($filePath)) {
    $cwd = if ($payload.cwd) { [string]$payload.cwd } else { (Get-Location).Path }
    $filePath = Join-Path $cwd $filePath
}

if (-not (Test-Path -LiteralPath $filePath -PathType Leaf)) { exit 0 }

$ext = [System.IO.Path]::GetExtension($filePath).ToLower()

# --- Map extension → linter ---
# Returns a scriptblock that runs the linter and returns ($exitCode, $output).
# Return $null to skip silently.

function Invoke-Linter {
    param([string]$File, [string]$Ext)

    switch ($Ext) {
        { $_ -in @(".js", ".jsx", ".ts", ".tsx") } {
            if (-not (Get-Command npx -ErrorAction SilentlyContinue)) { return $null }
            # --no-eslintrc: skip project config; parse-only mode via --rule overrides
            # We only want syntax errors, not style. Use the parser flag.
            $args = @(
                "--yes", "eslint",
                "--no-eslintrc",
                "--parser-options=ecmaVersion:latest,sourceType:module",
                "--rule", '{"no-unused-vars":"off","no-undef":"off"}',
                "--format", "compact",
                $File
            )
            $result = & npx @args 2>&1
            return @{ ExitCode = $LASTEXITCODE; Output = ($result -join "`n") }
        }

        ".py" {
            if (-not (Get-Command python -ErrorAction SilentlyContinue) -and
                -not (Get-Command python3 -ErrorAction SilentlyContinue)) { return $null }
            $py = if (Get-Command python3 -ErrorAction SilentlyContinue) { "python3" } else { "python" }
            $result = & $py -m py_compile $File 2>&1
            return @{ ExitCode = $LASTEXITCODE; Output = ($result -join "`n") }
        }

        ".rb" {
            if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) { return $null }
            $result = & ruby -c $File 2>&1
            return @{ ExitCode = $LASTEXITCODE; Output = ($result -join "`n") }
        }

        ".go" {
            if (-not (Get-Command gofmt -ErrorAction SilentlyContinue)) { return $null }
            $result = & gofmt -e $File 2>&1
            return @{ ExitCode = $LASTEXITCODE; Output = ($result -join "`n") }
        }

        ".rs" {
            if (-not (Get-Command rustfmt -ErrorAction SilentlyContinue)) { return $null }
            $result = & rustfmt --check $File 2>&1
            return @{ ExitCode = $LASTEXITCODE; Output = ($result -join "`n") }
        }

        ".ps1" {
            # Use the PowerShell parser in-process -- no subprocess, fastest possible.
            $src = Get-Content -LiteralPath $File -Raw -Encoding UTF8
            $errors = $null
            [System.Management.Automation.Language.Parser]::ParseInput($src, [ref]$null, [ref]$errors) | Out-Null
            $parseErrors = @($errors | Where-Object { $_.ErrorId -ne "DiscoveredAssembly" })
            if ($parseErrors.Count -gt 0) {
                $msg = ($parseErrors | ForEach-Object { $_.Message }) -join "; "
                return @{ ExitCode = 1; Output = $msg }
            }
            return @{ ExitCode = 0; Output = "" }
        }

        ".json" {
            # In-process JSON parse -- no subprocess.
            try {
                Get-Content -LiteralPath $File -Raw -Encoding UTF8 | ConvertFrom-Json -ErrorAction Stop | Out-Null
                return @{ ExitCode = 0; Output = "" }
            } catch {
                return @{ ExitCode = 1; Output = $_.Exception.Message }
            }
        }

        # .yaml/.yml: skip unless a validator is on PATH
        { $_ -in @(".yaml", ".yml") } {
            if (Get-Command yamllint -ErrorAction SilentlyContinue) {
                $result = & yamllint -d relaxed $File 2>&1
                return @{ ExitCode = $LASTEXITCODE; Output = ($result -join "`n") }
            }
            if (Get-Command python -ErrorAction SilentlyContinue) {
                $result = & python -c "import sys, yaml; yaml.safe_load(open(sys.argv[1]))" $File 2>&1
                return @{ ExitCode = $LASTEXITCODE; Output = ($result -join "`n") }
            }
            return $null
        }

        default { return $null }
    }
}

# --- Run linter with timeout via background job ---
$lintResult = $null
try {
    $job = Start-Job -ScriptBlock {
        param($ScriptPath, $FilePath, $Ext)
        # Re-source the function inside the job
        . $ScriptPath
        Invoke-Linter -File $FilePath -Ext $Ext
    } -ArgumentList @($MyInvocation.ScriptName, $filePath, $ext)

    # Wait up to 10 seconds
    $completed = Wait-Job -Job $job -Timeout 10
    if ($completed) {
        $lintResult = Receive-Job -Job $job
    }
    Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
} catch {
    # If job mechanism fails (e.g., constrained runspace), fall back to inline
    try {
        $lintResult = Invoke-Linter -File $filePath -Ext $ext
    } catch {}
}

# Null means no linter available or extension not mapped -- exit silently
if ($null -eq $lintResult) { exit 0 }

if ($lintResult.ExitCode -ne 0) {
    $rawOutput = [string]$lintResult.Output
    $truncated = if ($rawOutput.Length -gt 500) { $rawOutput.Substring(0, 500) + "..." } else { $rawOutput }
    $msg = "LINT-GATE: Syntax error detected in $filePath after edit. Linter output: $truncated. Fix the syntax error before proceeding."
    [Console]::Error.WriteLine($msg)
}

exit 0
