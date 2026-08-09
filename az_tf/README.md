# デプロイ手順

`bootstrap/` と `az_tf/` の2段階構成。`bootstrap/` が共有リソースグループとtfstate用Storage Accountを作り、`az_tf/` がその中にFoundry・APIMなど本体を作る。

## なぜ2段階か

`az_tf/` のtfstateはAzure Storage Accountに保存するが、そのStorage Account自体を`az_tf/`が管理するstateで作ることはできない（backendが依存するリソースを、そのbackendを使うstateで作れないため）。そこで`bootstrap/`が先にリソースグループとStorage Accountを作り、`az_tf/`側は`data "azurerm_resource_group"`でそれを参照する。

## 初回デプロイ

### 1. bootstrapを適用

```bash
cd bootstrap
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

### 3. az_tfを適用

```bash
cd az_tf
terraform init -backend-config=backend.hcl
terraform apply
```

APIM（Consumption tier）の作成には数分かかる。

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

PowerShell用に整形済みのコマンドは `terraform output -json copilot_cli_powershell` から取得できる（teamごと、sensitive）。BYOK設定を入れるとそのセッションはGitHubホスト型モデルには繋がらなくなる点に注意。

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

bootstrapの`terraform destroy`は、RG内にTerraform管理外のリソースが残っていると**わざと失敗する**（`azurerm`プロバイダのデフォルト動作、`prevent_deletion_if_contains_resources = true`）。エラーメッセージに残存リソースの一覧が出るので、それを見て「消してよいか」を人間が判断してから、`az resource delete`で個別に消して`terraform destroy`をやり直す。「Application Insightsの自動生成リソース」の項を参照。この安全装置はあえて無効化していない。

## 遭遇した詰まりどころ

- **Cognitive Servicesの論理削除**: `terraform destroy`をTerraform経由で行わず、リソースグループ削除など外部から消すと、Cognitive Services（Foundry）アカウントは論理削除（soft-delete）状態で残る。同名で再作成しようとすると409 `FlagMustBeSetForRestore`エラーになるため、`az cognitiveservices account purge --location <loc> --resource-group <rg> --name <name>` で完全削除してから再apply。
- **Application Insightsの自動生成リソース**: App Insightsを作成すると、Azureが`microsoft.insights/actiongroups`（Application Insights Smart Detection）と`microsoft.alertsmanagement/smartDetectorAlertRules`（Failure Anomalies）をTerraform管理外で自動生成する。これらがRG内に残っているとTerraformの安全装置でRG削除が失敗する（`the Resource Group still contains Resources`、エラー本文に対象リソースIDが列挙される）。これは意図的に残してある安全装置なので無効化しない。対処は都度: エラーに出た一覧（または`az resource list --resource-group <rg> -o table`と`terraform state list`の差分）を人間が確認し、不要と判断したものだけ`az resource delete --resource-group <rg> --resource-type <type> --name <name>`で消してから`terraform destroy`をやり直す。
- **APIM Consumption tierのポリシー制約**: `rate-limit-by-key` / `quota` / `quota-by-key` はConsumption tierでは一切使えない（400 `ValidationError`）。プレーンな`rate-limit`（Product scopeかつ`subscription_required = true`であれば実質サブスクリプション単位）で代替する必要がある。
- **GitHub Copilot CLIは`/openai/deployments/{id}/...`パスを使わない**: `COPILOT_PROVIDER_TYPE=azure`のとき、CLIは`COPILOT_PROVIDER_BASE_URL`に指定したデプロイパスを無視し、常に`{host}/openai/v1/chat/completions`（モデル名はリクエストボディの`model`フィールド）を呼ぶ（`copilot --log-level debug`で確認可能）。`api_management_api.tf`に`/openai/v1/chat/completions`・`/openai/v1/embeddings`のoperationを用意していないと404 `Model not found`になる。副次効果として、この方式のおかげで`COPILOT_PROVIDER_BASE_URL`はデプロイ名を含まないゲートウェイURLだけでよく、`COPILOT_MODEL`を変えるだけでモデルを切り替えられる（[#4](../../issues/4)）。
