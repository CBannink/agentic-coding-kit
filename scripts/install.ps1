$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$bundle = Join-Path $root 'cli\dist\kit.cjs'
if (Test-Path -LiteralPath $bundle) {
    & node $bundle install @args
} else {
    $tsx = Join-Path $root 'cli\node_modules\tsx\dist\cli.mjs'
    & node $tsx (Join-Path $root 'cli\src\index.ts') install @args
}
exit $LASTEXITCODE
