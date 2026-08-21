<#
  bootstrap/ と az_tf/ を続けて実行するラッパースクリプト。
  2つのフォルダを行き来せず、このスクリプト1本で完結する。

  手順:
    1. bootstrap/ で terraform init & apply
    2. bootstrap の output を backend.hcl / terraform.tfvars に書き込み
    3. az_tf/ で terraform init & apply

  使い方:
    .\deploy.ps1                     # 確認プロンプトあり
    .\deploy.ps1 -AutoApprove        # 確認なしで適用
    .\deploy.ps1 -ResourcePrefix "my-prefix" -Location "japaneast"
#>
param(
    [string]$ResourcePrefix = "ai-prj-sample",
    [string]$Location       = "eastus2",
    [switch]$AutoApprove
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$RepoRoot     = Resolve-Path "$PSScriptRoot\..\.."
$BootstrapDir = Join-Path $RepoRoot "bootstrap"
$AzTfDir      = Join-Path $RepoRoot "az_tf"

$ApplyArgs = @("-input=false")
if ($AutoApprove) { $ApplyArgs += "-auto-approve" }

function Invoke-Tf {
    param([string]$WorkDir, [string[]]$TfArgs)
    Push-Location $WorkDir
    try {
        & terraform @TfArgs
        if ($LASTEXITCODE -ne 0) { throw "terraform $($TfArgs[0]) failed (exit $LASTEXITCODE)" }
    } finally {
        Pop-Location
    }
}

# --- Step 1: bootstrap ---
Write-Host ""
Write-Host "=== [1/3] bootstrap: terraform init & apply ===" -ForegroundColor Cyan

$varArgs = @("-var=resource_prefix=$ResourcePrefix", "-var=location=$Location")
Invoke-Tf $BootstrapDir @("init", "-input=false")
Invoke-Tf $BootstrapDir (@("apply") + $ApplyArgs + $varArgs)

# --- Step 2: write config files from bootstrap outputs ---
Write-Host ""
Write-Host "=== [2/3] Writing backend.hcl and terraform.tfvars ===" -ForegroundColor Cyan

Push-Location $BootstrapDir
try {
    $outputs = (terraform output -json) | ConvertFrom-Json
} finally {
    Pop-Location
}

$RgName        = $outputs.resource_group_name.value
$NameSuffix    = $outputs.name_suffix.value
$SaName        = $outputs.storage_account_name.value
$ContainerName = $outputs.container_name.value

@"
resource_group_name  = "$RgName"
storage_account_name = "$SaName"
container_name       = "$ContainerName"
key                  = "az_tf.tfstate"
use_azuread_auth     = true
"@ | Set-Content -Path (Join-Path $AzTfDir "backend.hcl") -Encoding utf8

@"
resource_group_name = "$RgName"
name_suffix         = "$NameSuffix"
"@ | Set-Content -Path (Join-Path $AzTfDir "terraform.tfvars") -Encoding utf8

Write-Host "  resource_group_name  = $RgName"
Write-Host "  storage_account_name = $SaName"
Write-Host "  name_suffix          = $NameSuffix"

# --- Step 3: az_tf ---
Write-Host ""
Write-Host "=== [3/3] az_tf: terraform init & apply ===" -ForegroundColor Cyan

Invoke-Tf $AzTfDir @("init", "-input=false", "-backend-config=backend.hcl", "-reconfigure")
Invoke-Tf $AzTfDir (@("apply") + $ApplyArgs)

Write-Host ""
Write-Host "=== Done ===" -ForegroundColor Green
