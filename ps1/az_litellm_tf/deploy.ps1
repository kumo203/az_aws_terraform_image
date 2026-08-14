<#
  az_litellm_tf/*.tf のps1版。
  Foundry(AIServices) + モデルデプロイ + Foundry Project + Key Vault + Postgres Flexible
  Server + Container Apps(LiteLLM Proxy) を、この順で作る。az_tf/とは完全に独立していて、
  同じ共有リソースグループ(bootstrap/が作成)の中に、名前が衝突しない別プレフィックスで並走する。

  前提: bootstrap/deploy.ps1 を先に実行し、出てきた resource_group_name / name_suffix を
  -ResourceGroupName / -NameSuffix として渡すこと。

  LiteLLMのモデル/チーム/仮想キー設定はTerraform管理外(LiteLLMのAdmin API経由でPostgresに
  永続化)なので、このスクリプトの後に az_litellm_tf/README.md の「初回セットアップ」手順を
  手動で一度実行する必要がある(このps1もapply後に同じ手順をコンソールへ出力する)。
#>
param(
    [string]$ResourcePrefix = "ai-prj-litellm",
    [string]$Location = "eastus2",
    [Parameter(Mandatory)][string]$ResourceGroupName,
    [Parameter(Mandatory)][string]$NameSuffix,

    [string]$DeploymentSkuName = "GlobalStandard",
    [int]$DeploymentCapacity = 400,
    [hashtable]$ModelDeployments = @{
        "gpt-5.6-luna"  = @{ version = "2026-07-09" }
        "gpt-5.6-terra" = @{ version = "2026-07-09" }
        "gpt-5.6-sol"   = @{ version = "2026-07-09" }
    },
    [string]$ApiVersion = "2024-06-01",

    [string]$KeyVaultSkuName = "standard",
    [bool]$KeyVaultPurgeProtectionEnabled = $false,

    # サブスクリプションによっては$Locationの主要リージョン(eastus2等)でPostgres Flexible
    # Serverの新規作成が"Subscriptions are restricted from provisioning in this region"で
    # 拒否されることがある(az postgres flexible-server list-skus --location <loc> の reason で
    # 確認できる)。その場合だけ別リージョンを指定する。他のリソースは全て$Locationのまま。
    [string]$PostgresLocation,
    [string]$PostgresSkuName = "Standard_B1ms",
    [string]$PostgresTier = "Burstable",
    [int]$PostgresStorageGb = 32,
    [string]$PostgresVersion = "16",
    [string]$PostgresAdminUsername = "litellmadmin",
    [string]$PostgresDatabaseName = "litellm",
    [string[]]$PostgresAdminSourceIpRanges = @(),
    [int]$PostgresBackupRetentionDays = 7,
    [bool]$PostgresGeoRedundantBackupEnabled = $false,

    [string]$LitellmImageRepository = "ghcr.io/berriai/litellm-database",
    # ghcr.io/berriai/litellm-database のタグ一覧から現在の安定版を確認して指定すること。
    # latest/main-latest は使わない(スケールtoゼロ再起動ごとにpullし直しバージョンがブレる)。
    [Parameter(Mandatory)][string]$LitellmImageTag,
    [int]$LitellmMinReplicas = 0,
    [int]$LitellmMaxReplicas = 2,
    [double]$LitellmContainerCpu = 0.5,
    [string]$LitellmContainerMemory = "1Gi",
    [int]$LitellmTargetPort = 4000
)

. "$PSScriptRoot\..\common\Common.ps1"
Assert-CliInstalled az

$cognitiveApiVersion = "2025-06-01"  # az_tf/deploy.ps1と同じ注意: 必要に応じて確認・調整

# ---------------------------------------------------------------------------
# 0. リソースグループの存在確認
# ---------------------------------------------------------------------------
Write-Step "リソースグループ $ResourceGroupName を確認"
$rg = Invoke-AzJson @("group", "show", "--name", $ResourceGroupName)
if (-not $rg) {
    throw "リソースグループ '$ResourceGroupName' が見つかりません。先に bootstrap/deploy.ps1 を実行してください。"
}
$location = $rg.location
if (-not $PostgresLocation) { $PostgresLocation = $location }
$currentObjectId = Get-CurrentAzObjectId

# ---------------------------------------------------------------------------
# 1. Foundry (az_tf/deploy.ps1と同じ手順、別名前空間)
# ---------------------------------------------------------------------------
$foundryName = "$ResourcePrefix-$NameSuffix-foundry"
Write-Step "Foundryアカウント $foundryName を確認"
$foundry = Invoke-AzJson @("cognitiveservices", "account", "show", "--name", $foundryName, "--resource-group", $ResourceGroupName)
if ($foundry) {
    Write-Skip "cognitive account '$foundryName'"
} else {
    Invoke-Az @(
        "cognitiveservices", "account", "create",
        "--name", $foundryName, "--resource-group", $ResourceGroupName,
        "--location", $location, "--kind", "AIServices", "--sku", "S0",
        "--custom-domain", $foundryName, "--yes"
    ) | Out-Null
    $foundry = Invoke-AzJson @("cognitiveservices", "account", "show", "--name", $foundryName, "--resource-group", $ResourceGroupName)
}

if ($foundry.identity.type -ne "SystemAssigned") {
    Write-Step "Foundryアカウントに system-assigned identity を付与"
    Invoke-Az @("resource", "update", "--ids", $foundry.id, "--set", "identity.type=SystemAssigned") | Out-Null
}
if (-not $foundry.properties.allowProjectManagement) {
    Write-Step "Foundryで project management を有効化"
    Invoke-Az @("resource", "update", "--ids", $foundry.id, "--set", "properties.allowProjectManagement=true") | Out-Null
}

foreach ($modelName in $ModelDeployments.Keys) {
    $version = $ModelDeployments[$modelName].version
    Write-Step "モデルデプロイ '$modelName' (version $version) を確認"
    $deployment = Invoke-AzJson @(
        "cognitiveservices", "account", "deployment", "show",
        "--name", $foundryName, "--resource-group", $ResourceGroupName, "--deployment-name", $modelName
    )
    if ($deployment) {
        Write-Skip "deployment '$modelName'"
        continue
    }
    Invoke-Az @(
        "cognitiveservices", "account", "deployment", "create",
        "--name", $foundryName, "--resource-group", $ResourceGroupName,
        "--deployment-name", $modelName, "--model-name", $modelName, "--model-version", $version,
        "--model-format", "OpenAI", "--sku-name", $DeploymentSkuName, "--sku-capacity", $DeploymentCapacity
    ) | Out-Null
}

$projectName = "$ResourcePrefix-$NameSuffix-project"
$projectUri = "https://management.azure.com$($foundry.id)/projects/${projectName}?api-version=$cognitiveApiVersion"
Write-Step "Foundry Project $projectName を確認"
$project = Invoke-AzJson @("rest", "--method", "get", "--url", $projectUri)
if ($project) {
    Write-Skip "foundry project '$projectName'"
} else {
    $projectBody = @{ location = $location; identity = @{ type = "SystemAssigned" }; properties = @{ displayName = $projectName } } | ConvertTo-Json -Depth 5 -Compress
    $projectBodyFile = New-TemporaryFile
    Set-Content -Path $projectBodyFile -Value $projectBody -Encoding utf8
    Invoke-Az @("rest", "--method", "put", "--url", $projectUri, "--body", "@$projectBodyFile") | Out-Null
    Remove-Item $projectBodyFile -ErrorAction SilentlyContinue
}

$foundryApiKey = (Invoke-AzJson @("cognitiveservices", "account", "keys", "list", "--name", $foundryName, "--resource-group", $ResourceGroupName)).key1

# ---------------------------------------------------------------------------
# 2. Log Analytics (Container Apps Environment用) + User Assigned Identity
# ---------------------------------------------------------------------------
$lawName = "$ResourcePrefix-$NameSuffix-law"
Write-Step "Log Analytics Workspace $lawName を確認"
$law = Invoke-AzJson @("monitor", "log-analytics", "workspace", "show", "--resource-group", $ResourceGroupName, "--workspace-name", $lawName)
if ($law) {
    Write-Skip "log analytics workspace '$lawName'"
} else {
    Invoke-Az @(
        "monitor", "log-analytics", "workspace", "create",
        "--resource-group", $ResourceGroupName, "--workspace-name", $lawName, "--location", $location, "--sku", "PerGB2018"
    ) | Out-Null
    $law = Invoke-AzJson @("monitor", "log-analytics", "workspace", "show", "--resource-group", $ResourceGroupName, "--workspace-name", $lawName)
}

$uaiName = "$ResourcePrefix-$NameSuffix-litellm-id"
Write-Step "User Assigned Identity $uaiName を確認"
# SystemAssignedではなくUAIを使う理由: Key Vaultのロール付与(後述)をContainer App作成前に
# 済ませて伝播を待てるようにするため(先にIDが存在しないと権限を先付けできない)。
$uai = Invoke-AzJson @("identity", "show", "--name", $uaiName, "--resource-group", $ResourceGroupName)
if ($uai) {
    Write-Skip "user assigned identity '$uaiName'"
} else {
    Invoke-Az @("identity", "create", "--name", $uaiName, "--resource-group", $ResourceGroupName, "--location", $location) | Out-Null
    $uai = Invoke-AzJson @("identity", "show", "--name", $uaiName, "--resource-group", $ResourceGroupName)
}

# ---------------------------------------------------------------------------
# 3. Key Vault + シークレット
# ---------------------------------------------------------------------------
# Key Vault名はグローバル一意かつ24文字以内という制約があり、"$ResourcePrefix-$NameSuffix-kv"
# だと既定値(ai-prj-litellm)でも26文字になり超過する。bootstrap/のStorage Account名と同じ理由で、
# resource_prefixを使わない短い固定プレフィックスに倒す。
$kvNameCandidate = "ai-litellm-$NameSuffix-kv"
if ($kvNameCandidate.Length -gt 24) {
    throw "NameSuffix '$NameSuffix' が長すぎてKey Vault名(24文字以内)を構成できません。"
}
$kvName = $kvNameCandidate
Write-Step "Key Vault $kvName を確認"
$kv = Invoke-AzJson @("keyvault", "show", "--name", $kvName, "--resource-group", $ResourceGroupName)
if ($kv) {
    Write-Skip "key vault '$kvName'"
} else {
    $kvArgs = @(
        "keyvault", "create",
        "--name", $kvName, "--resource-group", $ResourceGroupName, "--location", $location,
        "--sku", $KeyVaultSkuName, "--enable-rbac-authorization", "true",
        "--retention-days", "7"
    )
    if ($KeyVaultPurgeProtectionEnabled) { $kvArgs += @("--enable-purge-protection", "true") }
    Invoke-Az $kvArgs | Out-Null
    $kv = Invoke-AzJson @("keyvault", "show", "--name", $kvName, "--resource-group", $ResourceGroupName)
}

Write-Step "実行者に Key Vault Secrets Officer ロールを付与 (シークレット書き込み用)"
$officerAssignment = Invoke-AzJson @("role", "assignment", "list", "--assignee", $currentObjectId, "--scope", $kv.id, "--role", "Key Vault Secrets Officer")
if ($officerAssignment -and $officerAssignment.Count -gt 0) {
    Write-Skip "role assignment 'Key Vault Secrets Officer' for current user"
} else {
    Invoke-Az @("role", "assignment", "create", "--role", "Key Vault Secrets Officer", "--assignee-object-id", $currentObjectId, "--assignee-principal-type", "User", "--scope", $kv.id) | Out-Null
    Wait-ForPropagation -Reason "Key Vault Secrets OfficerロールのAAD伝播待ち" -Seconds 90
}

Write-Step "Key Vault Secrets User ロールをContainer App用UAIに付与 (シークレット読み取り用)"
$userAssignment = Invoke-AzJson @("role", "assignment", "list", "--assignee", $uai.principalId, "--scope", $kv.id, "--role", "Key Vault Secrets User")
if ($userAssignment -and $userAssignment.Count -gt 0) {
    Write-Skip "role assignment 'Key Vault Secrets User' for litellm UAI"
} else {
    Invoke-Az @("role", "assignment", "create", "--role", "Key Vault Secrets User", "--assignee-object-id", $uai.principalId, "--assignee-principal-type", "ServicePrincipal", "--scope", $kv.id) | Out-Null
    Wait-ForPropagation -Reason "Key Vault Secrets UserロールのAAD伝播待ち" -Seconds 90
}

function Set-KvSecretIfMissing {
    param([string]$Name, [string]$Value)
    $existing = Invoke-AzJson @("keyvault", "secret", "show", "--vault-name", $kvName, "--name", $Name)
    if ($existing) {
        Write-Skip "key vault secret '$Name'"
        return $existing
    }
    Invoke-Az @("keyvault", "secret", "set", "--vault-name", $kvName, "--name", $Name, "--value", $Value) | Out-Null
    return Invoke-AzJson @("keyvault", "secret", "show", "--vault-name", $kvName, "--name", $Name)
}

Write-Step "LiteLLMマスターキー(sk-プレフィックス)をKey Vaultへ保存"
$litellmMasterKey = "sk-" + (New-RandomPassword -Length 32)
$litellmMasterKeySecret = Set-KvSecretIfMissing -Name "litellm-master-key" -Value $litellmMasterKey
if (Invoke-AzJson @("keyvault", "secret", "show", "--vault-name", $kvName, "--name", "litellm-master-key")) {
    # 既存の場合は生成した値ではなく実際の保存値を採用(出力にも使う)
    $litellmMasterKey = $litellmMasterKeySecret.value
}

Write-Step "Postgres管理者パスワードをKey Vaultへ保存"
$postgresAdminPassword = New-RandomPassword -Length 24
$postgresAdminSecret = Set-KvSecretIfMissing -Name "postgres-admin-password" -Value $postgresAdminPassword
$postgresAdminPassword = $postgresAdminSecret.value

Write-Step "Foundry APIキーをKey Vaultへ保存"
Set-KvSecretIfMissing -Name "foundry-api-key" -Value $foundryApiKey | Out-Null

# ---------------------------------------------------------------------------
# 4. Postgres Flexible Server
# ---------------------------------------------------------------------------
$pgName = "$ResourcePrefix-$NameSuffix-pg"
Write-Step "Postgres Flexible Server $pgName を確認 (作成には数分かかります)"
$pg = Invoke-AzJson @("postgres", "flexible-server", "show", "--name", $pgName, "--resource-group", $ResourceGroupName)
if ($pg) {
    Write-Skip "postgres flexible-server '$pgName'"
} else {
    Invoke-Az @(
        "postgres", "flexible-server", "create",
        "--name", $pgName, "--resource-group", $ResourceGroupName, "--location", $PostgresLocation,
        "--admin-user", $PostgresAdminUsername, "--admin-password", $postgresAdminPassword,
        "--sku-name", $PostgresSkuName, "--tier", $PostgresTier, "--version", $PostgresVersion,
        "--storage-size", $PostgresStorageGb,
        "--backup-retention", $PostgresBackupRetentionDays,
        "--geo-redundant-backup", $(if ($PostgresGeoRedundantBackupEnabled) { "Enabled" } else { "Disabled" }),
        # "None"/"Disabled"はパブリックアクセス自体を無効化してしまい、その場合
        # firewall-rule操作自体が使えなくなる(実際に確認済み)。terraform版の
        # public_network_access_enabled=true相当にするには"Enabled"を指定し、
        # 個別の許可はfirewall-ruleリソース側(既定は空=全拒否)で追加する。
        "--public-access", "Enabled",
        "--yes"
    ) | Out-Null
    $pg = Invoke-AzJson @("postgres", "flexible-server", "show", "--name", $pgName, "--resource-group", $ResourceGroupName)
}

Write-Step "データベース $PostgresDatabaseName を確認"
$db = Invoke-AzJson @("postgres", "flexible-server", "db", "show", "--server-name", $pgName, "--resource-group", $ResourceGroupName, "--name", $PostgresDatabaseName)
if ($db) {
    Write-Skip "postgres database '$PostgresDatabaseName'"
} else {
    Invoke-Az @("postgres", "flexible-server", "db", "create", "--server-name", $pgName, "--resource-group", $ResourceGroupName, "--name", $PostgresDatabaseName) | Out-Null
}

function Set-PostgresFirewallRuleIfMissing {
    param([string]$Name, [string]$StartIp, [string]$EndIp)
    $existing = Invoke-AzJson @("postgres", "flexible-server", "firewall-rule", "show", "--name", $Name, "--server-name", $pgName, "--resource-group", $ResourceGroupName)
    if ($existing) {
        Write-Skip "firewall rule '$Name'"
        return
    }
    Invoke-Az @(
        "postgres", "flexible-server", "firewall-rule", "create",
        "--name", $Name, "--server-name", $pgName, "--resource-group", $ResourceGroupName,
        "--start-ip-address", $StartIp, "--end-ip-address", $EndIp
    ) | Out-Null
}

Write-Step "ファイアウォールルール 'allow-azure-services' を確認 (Azureサービス全体を許可する特殊ルール)"
Set-PostgresFirewallRuleIfMissing -Name "allow-azure-services" -StartIp "0.0.0.0" -EndIp "0.0.0.0"

for ($i = 0; $i -lt $PostgresAdminSourceIpRanges.Count; $i++) {
    $ip = $PostgresAdminSourceIpRanges[$i]
    Write-Step "ファイアウォールルール 'admin-workstation-$i' ($ip) を確認"
    Set-PostgresFirewallRuleIfMissing -Name "admin-workstation-$i" -StartIp $ip -EndIp $ip
}

Write-Step "Postgres接続文字列をKey Vaultへ保存"
$postgresConnectionString = "postgresql://${PostgresAdminUsername}:${postgresAdminPassword}@$($pg.fullyQualifiedDomainName):5432/${PostgresDatabaseName}?sslmode=require"
$postgresConnSecret = Set-KvSecretIfMissing -Name "postgres-connection-string" -Value $postgresConnectionString
$postgresConnectionSecretId = $postgresConnSecret.id
$litellmMasterKeySecretId = (Invoke-AzJson @("keyvault", "secret", "show", "--vault-name", $kvName, "--name", "litellm-master-key")).id

# ---------------------------------------------------------------------------
# 5. Container Apps Environment + LiteLLM Proxy
# ---------------------------------------------------------------------------
$caeName = "$ResourcePrefix-$NameSuffix-cae"
Write-Step "Container App Environment $caeName を確認"
$cae = Invoke-AzJson @("containerapp", "env", "show", "--name", $caeName, "--resource-group", $ResourceGroupName)
if ($cae) {
    Write-Skip "container app environment '$caeName'"
} else {
    $lawKeys = Invoke-AzJson @("monitor", "log-analytics", "workspace", "get-shared-keys", "--resource-group", $ResourceGroupName, "--workspace-name", $lawName)
    Invoke-Az @(
        "containerapp", "env", "create",
        "--name", $caeName, "--resource-group", $ResourceGroupName, "--location", $location,
        "--logs-workspace-id", $law.customerId, "--logs-workspace-key", $lawKeys.primarySharedKey
    ) | Out-Null
    $cae = Invoke-AzJson @("containerapp", "env", "show", "--name", $caeName, "--resource-group", $ResourceGroupName)
}

$foundrySecretUri = (Invoke-AzJson @("keyvault", "secret", "show", "--vault-name", $kvName, "--name", "foundry-api-key")).id

# LiteLLMの /model/new (STORE_MODEL_IN_DB=True) は、実機検証したところこのイメージでは
# DBに何も書き込まれず(LiteLLM_Configテーブルが常に空)、コンテナが再起動/コールドスタートする
# たびにモデルが消える不具合を実際に踏んだ。動的登録に頼らず、terraformのmodel_deploymentsと
# 同じ内容をconfig.yamlとして焼き込み、起動時に毎回読み込ませる(値が変わることは滅多にないため
# 静的定義の方が確実)。api_keyはyaml内に生値を書かず os.environ/FOUNDRY_API_KEY 参照にする。
$modelListYaml = ($ModelDeployments.Keys | ForEach-Object {
    @"
  - model_name: $_
    litellm_params:
      model: azure/$_
      api_base: $($foundry.properties.endpoint)
      api_key: os.environ/FOUNDRY_API_KEY
      api_version: "$ApiVersion"
"@
}) -join "`n"
$litellmConfigYaml = @"
model_list:
$modelListYaml
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY
  database_url: os.environ/DATABASE_URL
  store_model_in_db: true
"@
$litellmConfigB64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($litellmConfigYaml))

$appName = "$ResourcePrefix-$NameSuffix-litellm"
Write-Step "Container App $appName (LiteLLM Proxy) を確認"
$app = Invoke-AzJson @("containerapp", "show", "--name", $appName, "--resource-group", $ResourceGroupName)
if ($app) {
    Write-Skip "container app '$appName'"
} else {
    # az containerapp create --yaml はスキーマの相性が悪く400エラーになったため、
    # CLIフラグ方式に切り替え(--secretsはkeyvaultref:<secret URI>,identityref:<UAI id>
    # という値を書くとKey Vault参照シークレットとして解釈される)。
    # 注意: liveness/readinessプローブ(terraform版のcontainer_apps.tf参照)はCLIフラグに
    # 対応するものがないため未設定(Container Appsの既定プローブに委ねる)。カスタムプローブが
    # 必要な場合は作成後に `az containerapp show -o yaml` で現在のスキーマを確認して
    # `az containerapp update --yaml` で追記すること。
    $secretsArg = @(
        "postgres-connection-string=keyvaultref:$($postgresConnSecret.id),identityref:$($uai.id)",
        "litellm-master-key=keyvaultref:$($litellmMasterKeySecretId),identityref:$($uai.id)",
        "foundry-api-key=keyvaultref:$foundrySecretUri,identityref:$($uai.id)"
    )
    $envVarsArg = @(
        "DATABASE_URL=secretref:postgres-connection-string",
        "LITELLM_MASTER_KEY=secretref:litellm-master-key",
        "FOUNDRY_API_KEY=secretref:foundry-api-key",
        "STORE_MODEL_IN_DB=True",
        "PORT=$LitellmTargetPort",
        "LITELLM_CONFIG_B64=$litellmConfigB64"
    )
    $createArgs = @(
        "containerapp", "create",
        "--name", $appName, "--resource-group", $ResourceGroupName,
        "--environment", $cae.id,
        "--user-assigned", $uai.id,
        "--image", "${LitellmImageRepository}:${LitellmImageTag}",
        "--cpu", "$LitellmContainerCpu", "--memory", $LitellmContainerMemory,
        "--ingress", "external", "--target-port", "$LitellmTargetPort",
        "--min-replicas", "$LitellmMinReplicas", "--max-replicas", "$LitellmMaxReplicas",
        "--secrets"
    ) + $secretsArg + @("--env-vars") + $envVarsArg
    Invoke-Az $createArgs | Out-Null
    $app = Invoke-AzJson @("containerapp", "show", "--name", $appName, "--resource-group", $ResourceGroupName)

    # 起動コマンドをconfig.yaml読み込み付きに上書きする。az containerapp create/updateの
    # --command/--args はnargs形式で、値に"-c"のような単独のダッシュ付きトークンを渡すと
    # argparseがそこで値の収集を止めてしまい "unrecognized arguments: -c" になる(実機で確認済み)。
    # az resource update --set は "path=<JSON値>" を1トークンとして渡すためこの問題を回避できる。
    $startupScript = 'echo "$LITELLM_CONFIG_B64" | base64 -d > /tmp/config.yaml && exec litellm --port $PORT --run_gunicorn --config /tmp/config.yaml'
    $argsJson = @($startupScript) | ConvertTo-Json -Compress
    Invoke-Az @(
        "resource", "update", "--ids", $app.id,
        "--set", 'properties.template.containers[0].command=["sh","-c"]',
        "--set", "properties.template.containers[0].args=$argsJson"
    ) | Out-Null
    $app = Invoke-AzJson @("containerapp", "show", "--name", $appName, "--resource-group", $ResourceGroupName)
}

$fqdn = $app.properties.configuration.ingress.fqdn

# ---------------------------------------------------------------------------
# 出力 + 初回セットアップ手順 (terraform output 相当)
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "===== az_litellm_tf 完了 =====" -ForegroundColor Green
Write-Host "foundry_endpoint    = $($foundry.properties.endpoint)  (内部専用)"
Write-Host "foundry_api_version = $ApiVersion"
Write-Host "litellm_gateway_url = https://$fqdn"
Write-Host "postgres_fqdn       = $($pg.fullyQualifiedDomainName)"
Write-Host "key_vault_uri       = $($kv.properties.vaultUri)"
Write-Host ""
Write-Host "----- 初回セットアップ手順 (README.md「LiteLLM Proxyの初回セットアップ」参照) -----"
Write-Host @"
モデル一覧(model_deployments全件)はconfig.yamlとしてコンテナ起動時に読み込まれるため、
/model/new での手動登録は不要(このイメージではSTORE_MODEL_IN_DBによるDB永続化が機能せず、
再起動でモデルが消える不具合を確認したため static config 方式に変更済み)。

1) ヘルスチェック(コールドスタート考慮でリトライ):
   curl https://$fqdn/health/liveliness
   curl https://$fqdn/v1/models -H "Authorization: Bearer <litellm_master_key>"

2) チーム作成 -> 仮想キー発行:
   curl -X POST https://$fqdn/team/new -H "Authorization: Bearer <litellm_master_key>" -H "Content-Type: application/json" -d '{"team_alias": "team-alpha"}'
   curl -X POST https://$fqdn/key/generate -H "Authorization: Bearer <litellm_master_key>" -H "Content-Type: application/json" -d '{"team_id": "<team_id>"}'

litellm_master_key / foundry_api_key / postgres_connection_string は sensitive につき
このコンソールには表示しません。取得するには:
   az keyvault secret show --vault-name $kvName --name litellm-master-key --query value -o tsv
   az keyvault secret show --vault-name $kvName --name foundry-api-key --query value -o tsv
   az keyvault secret show --vault-name $kvName --name postgres-connection-string --query value -o tsv
"@
