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

bootstrapの`terraform destroy`は、`prevent_deletion_if_contains_resources = false`によりRG内の管理外リソースをチェックせずAzure API側でRGごと削除する。「Application Insightsの自動生成リソース」の項を参照。

## 遭遇した詰まりどころ

- **Cognitive Servicesの論理削除**: `terraform destroy`をTerraform経由で行わず、リソースグループ削除など外部から消すと、Cognitive Services（Foundry）アカウントは論理削除（soft-delete）状態で残る。同名で再作成しようとすると409 `FlagMustBeSetForRestore`エラーになるため、`az cognitiveservices account purge --location <loc> --resource-group <rg> --name <name>` で完全削除してから再apply。
- **Application Insightsの自動生成リソース**: App Insightsを作成すると、Azureが`microsoft.insights/actiongroups`（Application Insights Smart Detection）と`microsoft.alertsmanagement/smartDetectorAlertRules`（Failure Anomalies）をTerraform管理外で自動生成する。これらがRG内に残っているとTerraformの安全装置でRG削除が失敗する（`the Resource Group still contains Resources`）。**対策済み**: `bootstrap/main.tf`の`provider "azurerm" { features { resource_group { prevent_deletion_if_contains_resources = false } } }` で、この安全装置自体を無効化してある（RGはAzure API側で中身ごと削除される）。RG削除前に管理外リソースを確認したい場合は、`az resource list --resource-group <rg> -o table`と`terraform state list`を突き合わせて事前に目視すること。
- **APIM Consumption tierのポリシー制約**: `rate-limit-by-key` / `quota` / `quota-by-key` はConsumption tierでは一切使えない（400 `ValidationError`）。プレーンな`rate-limit`（Product scopeかつ`subscription_required = true`であれば実質サブスクリプション単位）で代替する必要がある。
