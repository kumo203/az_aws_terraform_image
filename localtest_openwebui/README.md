# Open WebUI ローカル接続（一時検証用）

`az_litellm_tf/`（Azure Container Apps上のLiteLLM Proxy + Postgres Flexible
Server）に対し、ローカルで動かすOpen WebUIのDockerコンテナを接続するための一時検証用セットアップ。

- LLM呼び出し: Open WebUI → LiteLLM Gatewayを OpenAI互換エンドポイントとして利用
- アプリDB: Open WebUI自身のチャット履歴・ユーザー・設定は、ローカルsqliteではなく
  同じPostgres Flexible Server上の**別DB `openwebui`**（LiteLLM用の`litellm` DBとは別）に直接保存
- FW: ローカル検証用の一時的なIP許可であり、Terraformでは管理しない。`allow-local-ip.bat` /
  `remove-local-ip.bat` で都度追加・削除する

前提: `az_litellm_tf/` の環境が既にAzure上に構築済みで、このディレクトリ配下のスクリプトを実行する
PCで `az login` 済みであること（`terraform`コマンドは不要 - すべて`az` CLIでリソース名を自動検出し、
Key Vaultから直接シークレットを読む）。`setup-env.bat`はKey Vaultから`litellm-master-key`と
`postgres-connection-string`を読むため、実行者に対象Key Vaultの **Key Vault Secrets User**
（またはそれ以上）ロールが必要。サーバー/コンテナアプリ/Key Vaultの名前に`litellm`という文字列が
含まれることを前提に自動検出しているため、該当なし・複数該当でエラーになった場合は各スクリプトに
名前を明示的に渡すこと（例: `allow-local-ip.bat <server-name>`、`setup-env.bat -ServerName
... -ContainerAppName ... -KeyVaultName ...`）。

## 手順

1. `allow-local-ip.bat` を実行し、このPCのグローバルIPをPostgresのFWで一時的に許可する
2. `create-openwebui-db.bat` を実行し、Postgres上に `openwebui` データベースを作成する（初回のみ）
3. `setup-env.bat` を実行し、`.env` を自動生成する
   - `DATABASE_URL`（`openwebui`データベースへの接続文字列）
   - `OPENAI_API_BASE_URL` / `OPENAI_API_KEY`（LiteLLMで新規発行した仮想キー。マスターキーは使わない）
   - `WEBUI_SECRET_KEY`（ランダム生成）
4. LiteLLM側にモデルが未登録の場合は、先に `az_litellm_tf/README.md` の「LiteLLM
   Proxyの初回セットアップ」章にある `/model/new` 登録を実施しておく
   （`curl <gateway>/v1/models -H "Authorization: Bearer <virtual key>"` が空なら未登録）
5. `docker compose up -d` でOpen WebUIを起動する
6. ブラウザで `http://localhost:3000` を開き、初回ユーザー登録後、チャット画面でLiteLLM経由のモデルが選択・応答できることを確認する
7. 検証が終わったら `docker compose down` でコンテナを停止し、`remove-local-ip.bat`
   でPostgresの一時FWルールを削除する

## 補足

- `.env` は `localtest_openwebui/.env` としてローカルにのみ生成され、`.gitignore` により追跡対象外
- `setup-env.bat` は再実行するたびに新しい仮想キーを発行して `.env` を上書きする（古いキーはLiteLLM
  Admin UI/APIから手動で失効させること）
- `DATABASE_URL` はLiteLLM用の管理者ログイン情報をそのまま再利用している（同一サーバー上の別DBに向けているだけ）。恒久運用する場合は
  `openwebui` 専用のPostgresロールを別途作成することを推奨
- LiteLLMのAdmin UI（`<gateway>/ui`）にログインする際は `show-master-key.bat` を実行するとログイン情報
  （Username: `admin` / Password: `LITELLM_MASTER_KEY`の値）を表示できる
