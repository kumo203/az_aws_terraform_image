# 残作業

`aws_bootstrap/`・`aws_tf/`ともに実際にAWSへ`apply`済み。エンドツーエンド（API Gateway → Lambda → Bedrock Mantle → Grok 4.3）の疎通、CloudWatch Logsへのリクエスト/レスポンスログ記録、CloudWatchカスタムメトリクス（`GenAIGateway`namespace、`PromptTokens`/`CompletionTokens`/`TotalTokens`）の記録まで確認済み。IAMポリシーも`bedrock:*`から最小権限2つ（`bedrock-mantle:CreateInference` + `bedrock-mantle:CallWithBearerToken`、詳細は`README.md`の「遭遇した詰まりどころ」参照）に絞り込み済み。

## 再現手順（環境を作り直す場合）

1. `cd aws_bootstrap && terraform apply` → `terraform output`で`state_bucket_name` / `lock_table_name` / `name_suffix`を控える
2. `aws_tf/backend.hcl`・`aws_tf/terraform.tfvars`のプレースホルダを1の値で置き換える（このリポジトリではプレースホルダのままコミットしてあるので、都度ローカルで埋める運用。az_tfと同じ方式）
3. `cd aws_tf && terraform init -backend-config=backend.hcl && terraform apply`
4. `terraform output -raw apigw_invoke_url` / `terraform output -json apigw_api_keys` でチームキーを取得し、`/chat/completions`にcurlしてGrokの応答が返ることを確認

## 未実施・残っていること

- レート制限（usage planのthrottle/quota）が実際に429を返すかの負荷テストは未実施（機能自体はAWS API Gatewayのusage plan標準機能なので動作は期待できるが、実際にレート超過させて確認はしていない）
- `aws_api_gateway_stage`が`aws_api_gateway_account`のCloudWatchロール設定を待たずに動いて初回applyが1回失敗した（`depends_on`追加で解消済み、`api_gateway.tf`参照）。同種のIAM/設定伝播待ちが他にも潜んでいないか、複数回のdestroy→apply再現テストはしていない
