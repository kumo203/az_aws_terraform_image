[CmdletBinding()]
param(
    # Overrides for auto-detection below, in case there's more than one match
    # in the subscription/resource group.
    [string]$ServerName,
    [string]$ContainerAppName,
    [string]$KeyVaultName
)

# Generates localtest_openwebui/.env using only the az CLI (no terraform command / no
# az_litellm_tf checkout required):
# - auto-detects the LiteLLM Postgres server, Container App and Key Vault by
#   name (matching "litellm"), then reads the gateway FQDN and secrets
#   straight from Azure
# - derives an "openwebui" DATABASE_URL from LiteLLM's own connection string
#   (same admin login, different database name)
# - issues a fresh LiteLLM virtual key via /key/generate (never reuses the
#   master key)
# - writes a fresh WEBUI_SECRET_KEY
#
# Re-run any time to rotate the virtual key / secret; overwrites .env.
#
# Filtering is done in PowerShell (ConvertFrom-Json + Where-Object) rather
# than via az CLI's --query JMESPath filters: az on Windows is a .cmd shim,
# and PowerShell mangles the quoting of `[?contains(name,'x')]`-style
# expressions when invoking it, so plain property-path --query only.

$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-AzJson {
    param([string[]]$Arguments)
    # $ErrorActionPreference='Continue' here is function-scoped only (doesn't
    # leak to the caller) - without it, az's stderr output (even a harmless
    # WARNING) becomes a terminating error under the script's 'Stop' setting.
    $ErrorActionPreference = 'Continue'
    $output = & az @Arguments -o json 2>&1
    $exitCode = $LASTEXITCODE

    $stdoutLines = $output | Where-Object { $_ -isnot [System.Management.Automation.ErrorRecord] }
    $stderrLines = $output | Where-Object { $_ -is [System.Management.Automation.ErrorRecord] }

    if ($exitCode -ne 0) {
        throw "az $($Arguments -join ' ') failed (exit $exitCode):`n$($stderrLines -join "`n")"
    }
    if ($stderrLines) {
        Write-Warning ($stderrLines -join "`n")
    }
    return ($stdoutLines -join "`n") | ConvertFrom-Json
}

$servers = Invoke-AzJson @('postgres', 'flexible-server', 'list')
if ($ServerName) {
    $matchedServer = $servers | Where-Object { $_.name -eq $ServerName } | Select-Object -First 1
} else {
    $matchedServer = $servers | Where-Object { $_.name -like '*litellm*' } | Select-Object -First 1
}
if (-not $matchedServer) {
    throw "Could not find a Postgres Flexible Server matching 'litellm'. Pass -ServerName explicitly."
}
$ServerName = $matchedServer.name
$rg = $matchedServer.resourceGroup

if (-not $ContainerAppName) {
    $apps = Invoke-AzJson @('containerapp', 'list', '--resource-group', $rg)
    $matchedApp = $apps | Where-Object { $_.name -like '*litellm*' } | Select-Object -First 1
    if (-not $matchedApp) {
        throw "Could not find a Container App matching 'litellm' in resource group $rg. Pass -ContainerAppName explicitly."
    }
    $ContainerAppName = $matchedApp.name
}

$appDetails = Invoke-AzJson @('containerapp', 'show', '--resource-group', $rg, '--name', $ContainerAppName)
$fqdn = $appDetails.properties.configuration.ingress.fqdn
if (-not $fqdn) {
    throw "Could not resolve the ingress FQDN for container app $ContainerAppName."
}
$gateway = "https://$fqdn"

if (-not $KeyVaultName) {
    $vaults = Invoke-AzJson @('keyvault', 'list', '--resource-group', $rg)
    $matchedVault = $vaults | Where-Object { $_.name -like '*litellm*' } | Select-Object -First 1
    if (-not $matchedVault) {
        throw "Could not find a Key Vault matching 'litellm' in resource group $rg. Pass -KeyVaultName explicitly."
    }
    $KeyVaultName = $matchedVault.name
}

$masterKeySecret = Invoke-AzJson @('keyvault', 'secret', 'show', '--vault-name', $KeyVaultName, '--name', 'litellm-master-key')
$pgConnSecret = Invoke-AzJson @('keyvault', 'secret', 'show', '--vault-name', $KeyVaultName, '--name', 'postgres-connection-string')
$masterKey = $masterKeySecret.value
$pgConnString = $pgConnSecret.value
if (-not $masterKey -or -not $pgConnString) {
    throw "Could not read secrets from Key Vault $KeyVaultName. Check you have the 'Key Vault Secrets User' RBAC role (or higher) on it."
}

$openWebUiDbUrl = $pgConnString -replace '/litellm\?', '/openwebui?'
if ($openWebUiDbUrl -eq $pgConnString) {
    throw "Could not derive the openwebui DB URL - expected '/litellm?' in the postgres connection string. Run create-openwebui-db.bat first if you haven't."
}

Write-Host "Requesting a new LiteLLM virtual key for Open WebUI..."
$body = @{ key_alias = "openwebui-local" } | ConvertTo-Json
$response = Invoke-RestMethod -Uri "$gateway/key/generate" -Method Post `
    -Headers @{ Authorization = "Bearer $masterKey" } `
    -ContentType "application/json" -Body $body

$virtualKey = $response.key
if (-not $virtualKey) {
    throw "LiteLLM did not return a key. Response: $($response | ConvertTo-Json -Depth 5)"
}

$webuiSecretKey = [guid]::NewGuid().ToString("N")

$envPath = Join-Path $scriptDir '.env'
$envContent = @"
DATABASE_URL=$openWebUiDbUrl
OPENAI_API_BASE_URL=$gateway/v1
OPENAI_API_KEY=$virtualKey
WEBUI_SECRET_KEY=$webuiSecretKey
"@
# Windows PowerShell 5.1's `-Encoding utf8` always writes a UTF-8 BOM, which
# breaks naive KEY=VALUE parsing (e.g. `export $(xargs) < .env`) on the first
# line. Write plain UTF-8 without a BOM instead, for both 5.1 and 7+.
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($envPath, $envContent + "`n", $utf8NoBom)

Write-Host "Wrote $envPath"
Write-Host "Virtual key alias: openwebui-local (revoke later via LiteLLM Admin UI/API if no longer needed)"
