# デプロイ手順

`bootstrap/` と `az_tf/` の2段階構成。`bootstrap/` が共有リソースグループとtfstate用Storage Accountを作り、`az_tf/` がその中にFoundry・APIMなど本体を作る。

## なぜ2段階か

`az_tf/` のtfstateはAzure Storage Accountに保存するが、そのStorage Account自体を`az_tf/`が管理するstateで作ることはできない（backendが依存するリソースを、そのbackendを使うstateで作れないため）。そこで`bootstrap/`が先にリソースグループとStorage Accountを作り、`az_tf/`側は`data "azurerm_resource_group"`でそれを参照する。

## 初回デプロイ

### 1. bootstrapを適用

`resource_prefix`のデフォルト値（`ai-prj-sample`）を変更する場合は、`bootstrap/`と`az_tf/`の両方で同じ値に揃えること（両モジュールが同一のリソースグループ名を組み立てるため）。デフォルトのまま使う場合は対応不要。

```bash
cd bootstrap
terraform init
terraform apply
```

```powershell
Set-Location bootstrap
terraform init
terraform apply
```

出力される3つの値を控える。

```bash
terraform output
# resource_group_name  = "ai-prj-sample-<suffix>-rg"
# name_suffix          = "<suffix>"
# storage_account_name = "aiprj<suffix>tfstate"
# container_name       = "tfstate"
```

```powershell
terraform output
# resource_group_name  = "ai-prj-sample-<suffix>-rg"
# name_suffix          = "<suffix>"
# storage_account_name = "aiprj<suffix>tfstate"
# container_name       = "tfstate"
```

### 2. az_tf側の設定ファイルを埋める

`az_tf/backend.hcl` と `az_tf/terraform.tfvars` のプレースホルダを、上記の出力値で置き換える。

```hcl
# az_tf/backend.hcl
resource_group_name  = "ai-prj-sample-<suffix>-rg"
storage_account_name = "aiprj<suffix>tfstate"
container_name        = "tfstate"
key                    = "az_tf.tfstate"
use_azuread_auth       = true
```

```hcl
# az_tf/terraform.tfvars
resource_group_name = "ai-prj-sample-<suffix>-rg"
name_suffix          = "<suffix>"
```

`name_suffix` を`az_tf/backend.hcl`の`resource_group_name`と一致させること（bootstrapが作った同一のRGを指す）。

`apim_publisher_email`（デフォルトは仮アドレス`aiops@example.com`、`az_tf/variables.tf`）も、実際に通知を受け取れる配信リストのメールアドレスに`terraform.tfvars`で上書きすること。

### 3. az_tfを適用

```bash
cd az_tf
terraform init -backend-config=backend.hcl
terraform apply
```

```powershell
Set-Location az_tf
terraform init -backend-config=backend.hcl
terraform apply
```

APIM（Consumption tier）の作成には数分かかる。

## 適用前に確認するTodo

- **`apim_publisher_email`を実配信リストに変更**（`variables.tf:73-77`）— デフォルトの`aiops@example.com`のままだとAPIMのサービス通知が届かない。
- **`model_deployments`のモデル名/バージョンを再確認**（`variables.tf:40-52`）— コード内コメントの通り、`az cognitiveservices account list-models`で現在のカタログと一致しているか確認する。カタログ側が更新されていると404等になる可能性がある。
- **チームへの配布はAPIMサブスクリプションキーのみ**（`output.tf:23-26`）— `apim_subscription_keys`の値を配布し、Foundry本体の生キー（`foundry_endpoint`関連）は配らない。
- **（任意）`copilot_teams`のレート制限方針を見直す**（`variables.tf:85-90`）— Consumption tierでは`rate-limit-by-key`/`quota`系が使えないため単純な`rate-limit`で代替している。`apim_sku_name`をConsumption以外に変更する場合は、チームごとの厳密なクォータ制御への見直しを検討する。

## GitHub Copilot CLIでの利用

```bash
GATEWAY=$(terraform output -raw apim_gateway_url)
KEY=$(terraform output -json apim_subscription_keys | python3 -c "import json,sys; print(json.load(sys.stdin)['team-alpha'])")

export COPILOT_PROVIDER_BASE_URL="$GATEWAY"
export COPILOT_PROVIDER_TYPE=azure
export COPILOT_PROVIDER_API_KEY="$KEY"
export COPILOT_MODEL="gpt-5.6-luna"   # gpt-5.6-terra / gpt-5.6-sol にも変更可

copilot -p "hello" --allow-all-tools
```

```powershell
$GATEWAY = terraform output -raw apim_gateway_url
$KEY = (terraform output -json apim_subscription_keys | ConvertFrom-Json).'team-alpha'

$env:COPILOT_PROVIDER_BASE_URL = $GATEWAY
$env:COPILOT_PROVIDER_TYPE = "azure"
$env:COPILOT_PROVIDER_API_KEY = $KEY
$env:COPILOT_MODEL = "gpt-5.6-luna"   # gpt-5.6-terra / gpt-5.6-sol にも変更可

copilot -p "hello" --allow-all-tools
```

PowerShell用に整形済みのコマンド（BASE_URL/API_KEY/TYPE/MODELの4つ）は `terraform output -json copilot_cli_powershell` から取得できる（teamごと、sensitive）。BYOK設定を入れるとそのセッションはGitHubホスト型モデルには繋がらなくなる点に注意。

## 権限について

`use_azuread_auth = true` のため、tfstateを操作する人/サービスプリンシパルには対象Storage Accountの `Storage Blob Data Contributor` ロールが必要（`bootstrap/main.tf`の`azurerm_role_assignment.state_access`で、bootstrap適用時点のサインイン中ユーザーに自動付与される）。別ユーザーが運用する場合は追加のロール割り当てが必要。

## 全体を作り直す場合

環境を作り直す（destroy → 再構成）ときは、`az_tf/`側が bootstrap のStorage Accountをtfstateバックエンドとして使っているため、**az_tf → bootstrap の順**でdestroyする。逆順にすると、az_tfのstateを保存しているStorage Accountを先に消すことになり、stateにアクセスできなくなる。

```bash
cd az_tf
terraform destroy   # 先に本体を全部消す
cd ../bootstrap
terraform destroy   # 最後にtfstate用インフラを消す
```

```powershell
Set-Location az_tf
terraform destroy   # 先に本体を全部消す
Set-Location ..\bootstrap
terraform destroy   # 最後にtfstate用インフラを消す
```

bootstrapの`terraform destroy`は、RG内にTerraform管理外のリソースが残っていると**わざと失敗する**（`azurerm`プロバイダのデフォルト動作、`prevent_deletion_if_contains_resources = true`）。エラーメッセージに残存リソースの一覧が出るので、それを見て「消してよいか」を人間が判断してから、`az resource delete`で個別に消して`terraform destroy`をやり直す。「Application Insightsの自動生成リソース」の項を参照。この安全装置はあえて無効化していない。

## 遭遇した詰まりどころ

- **Cognitive Servicesの論理削除**: `terraform destroy`をTerraform経由で行わず、リソースグループ削除など外部から消すと、Cognitive Services（Foundry）アカウントは論理削除（soft-delete）状態で残る。同名で再作成しようとすると409 `FlagMustBeSetForRestore`エラーになるため、`az cognitiveservices account purge --location <loc> --resource-group <rg> --name <name>` で完全削除してから再apply。
- **Application Insightsの自動生成リソース**: App Insightsを作成すると、Azureが`microsoft.insights/actiongroups`（Application Insights Smart Detection）と`microsoft.alertsmanagement/smartDetectorAlertRules`（Failure Anomalies）をTerraform管理外で自動生成する。これらがRG内に残っているとTerraformの安全装置でRG削除が失敗する（`the Resource Group still contains Resources`、エラー本文に対象リソースIDが列挙される）。これは意図的に残してある安全装置なので無効化しない。対処は都度: エラーに出た一覧（または`az resource list --resource-group <rg> -o table`と`terraform state list`の差分）を人間が確認し、不要と判断したものだけ`az resource delete --resource-group <rg> --resource-type <type> --name <name>`で消してから`terraform destroy`をやり直す。
- **APIM Consumption tierのポリシー制約**: `rate-limit-by-key` / `quota` / `quota-by-key` はConsumption tierでは一切使えない（400 `ValidationError`）。プレーンな`rate-limit`（Product scopeかつ`subscription_required = true`であれば実質サブスクリプション単位）で代替する必要がある。
- **GitHub Copilot CLIは`/openai/deployments/{id}/...`パスを使わない**: `COPILOT_PROVIDER_TYPE=azure`のとき、CLIは`COPILOT_PROVIDER_BASE_URL`に指定したデプロイパスを無視し、常に`{host}/openai/v1/chat/completions`（モデル名はリクエストボディの`model`フィールド）を呼ぶ（`copilot --log-level debug`で確認可能）。`api_management_api.tf`に`/openai/v1/chat/completions`・`/openai/v1/embeddings`のoperationを用意していないと404 `Model not found`になる。副次効果として、この方式のおかげで`COPILOT_PROVIDER_BASE_URL`はデプロイ名を含まないゲートウェイURLだけでよく、`COPILOT_MODEL`を変えるだけでモデルを切り替えられる（[#4](../../issues/4)）。
- **GenAI gatewayポリシーもConsumption tierで一部制限**: ポータルの「Manage token consumption」(`llm-token-limit`) はDeveloper/Basic/Standard/Premium限定でConsumption非対応（`rate-limit-by-key`/`quota-by-key`と同じ系統）。一方「Track token usage」(`llm-emit-token-metric`) は全tier対応（gatewayに`consumption`も明記）なのでこちらのみ`aoai-api-policy.xml`に追加済み（`namespace="genai-gateway"`、dimension: Subscription ID / API ID）。
- **本文ロギングの上限**: `azurerm_api_management_diagnostic`の`body_bytes`は8192バイト（8KB）が固定上限（Azure側のハードリミット、変更不可）。さらにログエントリ全体（ヘッダー+本文+トレース）が32KBを超えるとAPIMは本文・トレースを丸ごと削除する仕様のため、`frontend_request`/`frontend_response`/`backend_request`/`backend_response`を全部8192で埋めると大きいプロンプトほど何も記録されなくなる逆効果になり得る。今回は`frontend_request`/`frontend_response`のみ設定（backendは同じ内容を素通しするだけなので実質重複）。`frontend_request`を明示すると、APIMの暗黙デフォルトである「クエリパラメータを全てマスク」が外れてしまう点に注意 — このAPIは`api-key`をクエリパラメータでも受け付けるため、`data_masking { query_params { mode = "Hide", value = "*" } }`を明示的に復元して塞いである。8KBを超える本文まで残したい場合は`log-to-eventhub`ポリシー（最大200KB）が別途必要。
