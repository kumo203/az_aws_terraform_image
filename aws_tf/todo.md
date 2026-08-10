# 残作業

`aws_bootstrap/`・`aws_tf/`のTerraformコードは書き終わって`terraform validate`とdry-run `plan`（ローカルbackendでの一時検証、実リソースは未作成）まで確認済み。実際のAWSへの`apply`はまだ行っていない。

## 1. aws_bootstrapをapply

```bash
cd aws_bootstrap
terraform apply
terraform output
```

出力される`state_bucket_name` / `lock_table_name` / `name_suffix`を控える。

## 2. aws_tfのbackend.hcl / terraform.tfvarsを埋める

`aws_tf/backend.hcl`の`bucket` / `dynamodb_table`、`aws_tf/terraform.tfvars`の`name_suffix`を、1で出た値に置き換える。

## 3. aws_tfをapply

```bash
cd aws_tf
terraform init -backend-config=backend.hcl
terraform apply
```

現時点の`bedrock_auth.tf`のIAMポリシーは`bedrock:*`のまま（暫定・広すぎる）。

## 4. 動作確認

```bash
terraform output -raw apigw_invoke_url
terraform output -json apigw_api_keys
```

チームのキーを使って実際にcurlで`/openai/v1/chat/completions`にPOSTし、200応答とGrokの返答を確認する。CloudWatch Logsに`mantle_proxy`のリクエスト/レスポンスログ（8KB切り詰め）が出ていること、CloudWatchメトリクス`GenAIGateway`にトークン数が記録されていることも確認する。

## 5. IAMポリシーを絞る

4で一度`bedrock:*`での動作を確認したら、`aws_tf/bedrock_auth.tf`の`aws_iam_user_policy.mantle_gateway`を狙いを絞ったポリシー（`bedrock:CallWithBearerToken`が有力な候補 — 短期API key発行時に見えた presigned URLの`Action=CallWithBearerToken`から推測）に変更し、`terraform apply`→4のcurlテストを再実行して動くことを確認する。動かなければ広げて再試行し、実際に動いた最小権限を確定させる。

## 6. README.mdに追記

5で確定した最小IAMポリシーと、apply〜動作確認までの一連の手順で他に詰まった点があれば、`aws_tf/README.md`の「遭遇した詰まりどころ」に相当する節を追記する（az_tfのREADMEと同じ形式）。
