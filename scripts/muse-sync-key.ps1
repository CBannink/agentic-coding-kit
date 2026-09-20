# Stores the Muse subscription key in OpenCode's auth file (serverless).
# Requires a prior `muse login` (device-code OAuth). Muse CLI maintains
# ~/.config/muse/auth.json itself; this script copies the api_key it already
# stores into OpenCode's auth.json as {"muse-sub": {"type": "api", ...}},
# which OpenCode reads from disk on every launch. No local server, background
# process, or environment-variable timing is involved. Re-run if Muse CLI
# ever rotates the key, then restart OpenCode.
$ErrorActionPreference = 'Stop'
$auth = Get-Content "$env:USERPROFILE\.config\muse\auth.json" -Raw | ConvertFrom-Json
$key = $auth.providers.meta.api_key
if (-not $key) { throw 'No api_key found in muse auth.json (providers.meta). Run `muse login` first.' }
$opencodeAuth = "$env:USERPROFILE\.local\share\opencode\auth.json"
$store = if (Test-Path -LiteralPath $opencodeAuth) { Get-Content $opencodeAuth -Raw | ConvertFrom-Json } else { [pscustomobject]@{} }
$store | Add-Member -NotePropertyName 'muse-sub' -NotePropertyValue ([pscustomobject]@{ type = 'api'; key = $key }) -Force
$store | ConvertTo-Json -Depth 10 | Set-Content $opencodeAuth
Write-Output 'muse-sub key stored in OpenCode auth.json.'
$headers = @{ Authorization = 'Bearer ' + $key }
$models = Invoke-RestMethod -Uri ($auth.providers.meta.api_base_url + '/models') -Headers $headers -TimeoutSec 30
Write-Output ('API check OK, models: ' + (($models.data | Select-Object -First 8).id -join ', '))
