# デプロイ手順

`bootstrap/` と `az_litellm_tf/` の2段階構成。`bootstrap/` が共有リソースグループとtfstate用Storage Accountを作り、`az_litellm_tf/` がその中にFoundry・Key Vault・PostgreSQL・Container Apps（LiteLLM Proxy）など本体を作る。

## 位置づけ：`az_tf/` との関係

このフォルダは `az_tf/`（Azure API Management による、Azureで最も安価なCopilot BYOKゲートウェイ）を**置き換えるものではない**。`az_tf/` は今後も本番として恒久的に稼働を続ける。

`az_litellm_tf/` は、AWS Bedrock・OpenAI・Anthropic等へのマルチクラウド対応や、他クラウドへの移植を見据えた**並走・実験用の環境**として別途構築するもので、以下の点で `az_tf/` と完全に独立している。

- **別Terraform state**（`backend.hcl`の`key`が`az_tf.tfstate`ではなく`az_litellm_tf.tfstate`）
- **別Azure AI Foundryアカウント**（`resource_prefix`が`ai-prj-sample`ではなく`ai-prj-litellm`のため、同一リソースグループ内でも名前が衝突しない）
- **別ゲートウェイ**（APIMではなくLiteLLM Proxy。認証もAPIMサブスクリプションキーではなくLiteLLMの仮想キー）

そのため `az_litellm_tf/` に対する`terraform apply`/`destroy`は `az_tf/` 側に一切影響しない。同一リージョンに2つのAIServicesアカウント（各3モデル×400TPM）が存在することになるため、GlobalStandardのリージョンクォータ上限には注意すること。

## なぜ2段階か

`az_litellm_tf/`のtfstateはAzure Storage Accountに保存するが、そのStorage Account自体を`az_litellm_tf/`が管理するstateで作ることはできない（backendが依存するリソースを、そのbackendを使うstateで作れないため）。そこで`bootstrap/`が先にリソースグループとStorage Accountを作り、`az_litellm_tf/`側は`data "azurerm_resource_group"`でそれを参照する（`az_tf/`と共用の同じ`bootstrap/`を使う）。

## 初回デプロイ

### 1. bootstrapを適用（`az_tf/`側で既に適用済みなら再適用不要）

```bash
cd bootstrap
terraform init
terraform apply
```

出力される値を控える。

```bash
terraform output
# resource_group_name  = "ai-prj-sample-<suffix>-rg"
# name_suffix          = "<suffix>"
# storage_account_name = "aiprj<suffix>tfstate"
# container_name       = "tfstate"
```

### 2. az_litellm_tf側の設定ファイルを埋める

`az_litellm_tf/backend.hcl` と `az_litellm_tf/terraform.tfvars` のプレースホルダを、上記の出力値で置き換える。

```hcl
# az_litellm_tf/backend.hcl
resource_group_name  = "ai-prj-sample-<suffix>-rg"
storage_account_name = "aiprj<suffix>tfstate"
container_name        = "tfstate"
key                    = "az_litellm_tf.tfstate"   # az_tf.tfstateとは別のキー（重要）
use_azuread_auth       = true
```

```hcl
# az_litellm_tf/terraform.tfvars
resource_group_name = "ai-prj-sample-<suffix>-rg"
name_suffix         = "<suffix>"
litellm_image_tag   = "<GHCRで確認した最新安定版タグ>"
```

`litellm_image_tag`はデフォルト値を持たない必須変数。[ghcr.io/berriai/litellm-database](https://github.com/berriai/litellm/pkgs/container/litellm-database)のタグ一覧から現在の安定版を確認して指定すること。**`latest`/`main-latest`は使わない**（スケールtoゼロからの再起動のたびにイメージを再pullするため、タグが動くとLiteLLMのバージョン・Prismaスキーマが意図せず変わってしまう）。

### 3. az_litellm_tfを適用

```bash
cd az_litellm_tf
terraform init -backend-config=backend.hcl
terraform apply
```

Postgres Flexible Server・Container Apps Environmentの作成には数分かかる。

## 適用前に確認するTodo

- **`litellm_image_tag`を実在する安定版タグに設定**（`variables.tf`、デフォルトなし）。
- **`model_deployments`のモデル名/バージョンを再確認**（`variables.tf`）— `az cognitiveservices account list-models`で現在のカタログと一致しているか確認する。
- **`key_vault_purge_protection_enabled`の方針を決める**（既定`false`）— `false`だと`terraform destroy`がクリーンに通るが、Key Vault自体は7日間のsoft-delete状態を経る。`true`にする場合はteardown時に`az keyvault purge`が別途必要になる（Cognitive Servicesのsoft-delete gotchaと同種の注意）。
- **同一リージョンのAOAI GlobalStandardクォータ**— `az_tf/`のFoundryと合わせて2アカウント分（各3モデル×400TPM）を消費する点に注意。

## LiteLLM Proxyの初回セットアップ（Copilot CLIでの利用）

APIMと違い、モデル・チーム・仮想キーの設定はTerraformではなく**LiteLLMのAdmin API経由でPostgresに永続化**する。`terraform apply`後、以下を一度だけ手動で実行する（`terraform output bootstrap_instructions`にも同内容の手順が出力される）。

```bash
GATEWAY=$(terraform output -raw litellm_gateway_url)
MASTER_KEY=$(terraform output -raw litellm_master_key)
FOUNDRY_ENDPOINT=$(terraform output -raw foundry_endpoint)
FOUNDRY_KEY=$(terraform output -raw foundry_api_key)
API_VERSION=$(terraform output -raw foundry_api_version)

# 1) ヘルスチェック（スケールtoゼロからのコールドスタートを考慮しリトライ）
curl "$GATEWAY/health/liveliness"

# 2) Azureモデルを登録（3デプロイ分、繰り返す）
curl -X POST "$GATEWAY/model/new" \
  -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" \
  -d "{\"model_name\": \"gpt-5.6-luna\", \"litellm_params\": {\"model\": \"azure/gpt-5.6-luna\", \"api_base\": \"$FOUNDRY_ENDPOINT\", \"api_key\": \"$FOUNDRY_KEY\", \"api_version\": \"$API_VERSION\"}}"

# 3) チーム作成 → 仮想キー発行
curl -X POST "$GATEWAY/team/new" \
  -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"team_alias": "team-alpha"}'
# レスポンスの team_id を使って:
curl -X POST "$GATEWAY/key/generate" \
  -H "Authorization: Bearer $MASTER_KEY" -H "Content-Type: application/json" \
  -d '{"team_id": "<team_id>"}'
```

Copilot CLI側は、発行された**仮想キー**（マスターキーではない）を使う。

```bash
export COPILOT_PROVIDER_BASE_URL="$GATEWAY"
export COPILOT_PROVIDER_TYPE=azure   # 未検証。下記「詰まりどころ」参照
export COPILOT_PROVIDER_API_KEY="<virtual key>"
export COPILOT_MODEL="gpt-5.6-luna"

copilot -p "hello" --allow-all-tools
```

使用量は`GET $GATEWAY/spend/logs`またはLiteLLM Admin UIの使用量タブでPostgresから確認できる（APIMの`llm-emit-token-metric`に相当）。

## 権限について

`use_azuread_auth = true` のため、tfstateを操作する人/サービスプリンシパルには対象Storage Accountの `Storage Blob Data Contributor` ロールが必要（`bootstrap/main.tf`の`azurerm_role_assignment.state_access`）。Key Vaultへの書き込みはTerraform実行者に自動付与される`Key Vault Secrets Officer`ロール（`key_vault.tf`）で行われる。

## 全体を作り直す場合

`az_litellm_tf/`側が bootstrap のStorage Accountをtfstateバックエンドとして使っているため、**az_litellm_tf → bootstrap の順**でdestroyする（`az_tf/`が同じbootstrapを共有している場合は、`az_tf/`もdestroy済みであることを確認してから`bootstrap/`をdestroyする）。

```bash
cd az_litellm_tf
terraform destroy
cd ../bootstrap
terraform destroy   # az_tf/も含め、他に依存するstateが残っていないことを確認してから
```

## 遭遇しうる詰まりどころ

- **Cognitive Servicesの論理削除**: `az_tf/README.md`と同じ注意。`az cognitiveservices account purge`で対処。
- **Key Vaultの論理削除**: `key_vault_purge_protection_enabled=false`のままdestroyすると、Key Vaultはsoft-delete状態で7日間残る。同名で再作成しようとするとエラーになる場合は`az keyvault purge --name <name> --location <loc>`で完全削除。
- **`litellm-database`イメージが必須**: 無印`litellm`イメージでは`STORE_MODEL_IN_DB=True`利用時にPrismaクライアントが同梱されておらず起動時マイグレーションが失敗する。
- **コールドスタートのレイテンシ**: `min_replicas=0`のためアイドル後の最初のリクエストはコンテナ起動＋Prisma初期化＋Postgres初回接続が重なり数十秒かかることがある。`container_apps.tf`のprobe閾値は実測後に調整すること。
- **Postgresファイアウォールの「Azureサービス許可」ルール**: `postgres.tf`の`allow_azure_services`（`0.0.0.0`/`0.0.0.0`）は同一Azureテナント外のリソースからの接続試行も（資格情報が必要とはいえ）許してしまう。VNet/プライベートエンドポイントを使わないコスト最優先の設計上のトレードオフとして許容している。
- **GitHub Copilot CLIの`/openai/v1/...`パス仕様は未検証**: `az_tf/README.md`に記載の通り、Copilot CLIの`azure`プロバイダは常に`{host}/openai/v1/chat/completions`を叩く。LiteLLMの標準ルートが同じパスに応答するかは未確認のため、`copilot --log-level debug`で実際のリクエストパスを確認し、`COPILOT_PROVIDER_TYPE`が`azure`のままで良いか（あるいは`openai`にすべきか）を検証すること。
