$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bundle = Join-Path $root 'cli\dist\kit.cjs'
if (Test-Path -LiteralPath $bundle) { & node $bundle install --host opencode @args } else { & node (Join-Path $root 'cli\node_modules\tsx\dist\cli.mjs') (Join-Path $root 'cli\src\index.ts') install --host opencode @args }
exit $LASTEXITCODE
