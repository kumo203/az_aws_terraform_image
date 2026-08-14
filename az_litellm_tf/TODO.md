# 残件（Docker/Terraform起動後の作業リスト）

`feature/az_litellm_ver` ブランチ・worktree（`C:\home\az_aws_terraform_image.worktrees\az_litellm_ver\az_litellm_tf`）で実装済みだが、Terraform CLI（Docker daemon未起動のため）を実行できず未検証の項目、および実装時に判断が必要な残件。

## 1. 最優先：構文・スキーマ検証（Docker起動後すぐ実施） — 完了（2026-08-14）
`terraform apply`が実際に成功し、その後の`terraform destroy`も完走したことでazurerm `~>5.0`スキーマの問題は無いことを実証済み。

- [ ] `terraform fmt -check -diff -recursive` で整形差分を確認・適用
- [ ] `terraform init -backend-config=backend.hcl`（下記§2の値を埋めてから）
- [ ] `terraform validate`
- [ ] 特に以下は実装時にazurerm `~>5.0`（`.terraform.lock.hcl`固定バージョン）の実スキーマと突き合わせて要修正の可能性が高い（一般的な知識ベースで執筆したため未確認）:
  - `container_apps.tf`: `azurerm_container_app_environment.log_analytics_workspace_id` の引数名（バージョンによって別名の場合あり）
  - `container_apps.tf`: `secret { key_vault_secret_id, identity }` の正確な構文
  - `container_apps.tf`: `liveness_probe`/`readiness_probe` の引数名（`initial_delay` vs `initial_delay_seconds`、`timeout` vs `timeout_seconds`、`transport`の許容値など）
  - `postgres.tf`: `azurerm_postgresql_flexible_server` に`authentication`ブロック（パスワード認証を明示的に有効化する引数）が必要かどうか（バージョンによりデフォルト挙動が異なる可能性）

## 2. bootstrap出力値の反映（`az_tf/`と同じ共有RGの値を使う） — 完了（2026-08-14）

- [ ] `az_litellm_tf/backend.hcl` の `resource_group_name`/`storage_account_name` を bootstrap出力（`az_tf/backend.hcl`に既に埋めてある値と同じはず）で置き換え
- [ ] `az_litellm_tf/terraform.tfvars` の `resource_group_name`/`name_suffix` も同様に置き換え
- [ ] `litellm_image_tag` を実在する安定版タグに設定（[ghcr.io/berriai/litellm-database](https://github.com/berriai/litellm/pkgs/container/litellm-database) のタグ一覧を確認。`latest`/`main-latest`は不可）

## 3. apply前の事前確認 — 完了（2026-08-14）
TPMクォータは`az_tf`側が未構築だったため単独消費（3モデル×400TPM）で問題化せず。`destroy`後にクォータが`0`に戻ることも確認済み（詳細は[LITELLM_DB_PERSISTENCE_NEXT_STEPS.md](../../LITELLM_DB_PERSISTENCE_NEXT_STEPS.md)参照）。

- [ ] 同一リージョンでGlobalStandardのTPMクォータが `az_tf/`（3モデル×400TPM）＋ `az_litellm_tf/`（同じく3モデル×400TPM）の合計で上限を超えないか、Azureポータルまたは `az cognitiveservices usage list` 等で確認
- [ ] `random_password`（postgres_admin, litellm_master_key）が生成する文字列がAzure Postgresのパスワード要件・LiteLLMのキー要件を満たすか（長さ24/32、`-_.`のみの特殊文字）を初回apply後に実値で確認

## 4. `terraform apply` 実行・実機検証（README.mdの「LiteLLM Proxyの初回セットアップ」章の手順に対応） — 完了（2026-08-14、一部は課題2の決定により方式変更）

- [x] `terraform apply`（`az_litellm_tf/`、独立state）
- [x] `curl <litellm_gateway_url>/health/liveliness` でスケールtoゼロからのコールドスタート挙動を実測（~28秒） → probe閾値の追加調整は不要と判断
- [x] ~~`/model/new` で3モデルを登録~~ — 課題2の決定により静的config.yaml方式を維持することにしたため不要（`apply`だけで3モデルとも`/v1/models`に自動登録されることを確認済み）
- [x] `/team/new` → `/key/generate` で仮想キー発行
- [x] 仮想キーで直接 `/v1/chat/completions` を叩いて疎通確認（Open WebUI経由のブラウザ実機確認も実施）
- [x] Postgresに実際に接続できること（Open WebUI用DBのマイグレーション成功、LiteLLM側のPrisma管理テーブル存在）を確認済み

## 5. 最重要・go/no-go判断ポイント

- [ ] **Copilot CLIの`azure`プロバイダが叩く `{host}/openai/v1/chat/completions` パスに、LiteLLMが実際に応答するか未検証。** `copilot --log-level debug` で実リクエストパスを確認し、`COPILOT_PROVIDER_TYPE=azure`のままで良いか、`openai`に変えるべきかを判定する（README.md「詰まりどころ」参照）

## 6. その他

- [x] `az_litellm_tf/` はコミット済み・PR #11としてリモートにpush済み（2026-08-14時点でOPEN）
- [x] `az_tf/`側のAPIM経由Copilot利用は、この期間`az_tf`自体がこのRGにまだ存在しなかったため影響なし（課題1が未着手のまま）
