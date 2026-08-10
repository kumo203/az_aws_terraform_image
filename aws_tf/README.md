# Grok 4.3 (Amazon Bedrock Mantle) の呼び方

## 概要

`xai.grok-4.3` は他のBedrockモデルと違い、通常の `bedrock-runtime` エンドポイント（Invoke/Converse）では**呼べない**。専用の `bedrock-mantle` エンドポイント（OpenAI互換API）経由でのみアクセス可能。

| 項目 | 値 |
| --- | --- |
| Model ID | `xai.grok-4.3` |
| エンドポイント | `bedrock-mantle`（`bedrock-runtime`ではない） |
| ホスト | `bedrock-mantle.<region>.api.aws`（`.amazonaws.com`ではなく`.api.aws`） |
| 対応API | Chat Completions / Responses（Invoke・Converseは非対応） |
| 対応リージョン | us-east-1, us-east-2, us-west-2（2026-08時点、Geo/Global Cross-Regionは未対応） |

## 1. APIキーの発行

Bedrockコンソール → 「API keys」から発行する（IAMのSigV4ではなく、この専用API keyで認証する）。

```bash
# https://console.aws.amazon.com/bedrock/home#/api-keys から発行し、以下のように設定
export OPENAI_API_KEY="<発行したBedrock API key>"
export OPENAI_BASE_URL="https://bedrock-mantle.us-east-1.api.aws/openai/v1"
```

短期キー（コンソールの「Generate short-term API key」）は発行から最大12時間で失効する。長期運用には「long-term API key」を使う。

## 2. curlでの呼び出し

```bash
curl -s "$OPENAI_BASE_URL/chat/completions" \
  -H "Authorization: Bearer $OPENAI_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "xai.grok-4.3",
    "messages": [
      {"role": "user", "content": "Hello, this is a test message."}
    ]
  }'
```

## 3. OpenAI SDK (Python) での呼び出し

```python
from openai import OpenAI

client = OpenAI()  # OPENAI_API_KEY / OPENAI_BASE_URL を環境変数から読む

response = client.chat.completions.create(
    model="xai.grok-4.3",
    messages=[{"role": "user", "content": "Hello, this is a test message."}],
)
print(response.choices[0].message.content)
```

Responses APIを使う場合（ステートフルな会話管理、reasoning内容の暗号化保持に対応）:

```python
response = client.responses.create(
    model="xai.grok-4.3",
    input="Hello, this is a test message.",
    reasoning={"effort": "low"},  # none / low(デフォルト) / medium / high
)
print(response.output_text)
```

## デフォルト値の違い（OpenAI標準と異なる点）

- `temperature`: `0.7`（OpenAI標準は`1`）
- `top_p`: `0.95`（OpenAI標準は`1`）
- `max_completion_tokens`: `131072`
- `reasoning.effort`: 常時有効。デフォルト`low`。無効化するには`{"effort": "none"}`を明示。
- Chat Completions APIはreasoning tokenを返さない（reasoning内容を見たい場合はResponses APIを使う）。

## 遭遇した詰まりどころ

- **`bedrock-runtime`ではなく`bedrock-mantle`**: 通常のBedrockモデル呼び出しの癖で`bedrock-runtime.<region>.amazonaws.com`にPOSTすると、パス自体は認識されるが認証エラー（`Authentication failed: Please make sure your API Key is valid`）になる。Grok 4.3はモデルカード上も`bedrock-runtime`/`Invoke`/`Converse`が非対応と明記されている。
- **ホスト名は`.api.aws`ドメイン**: `bedrock-mantle.<region>.amazonaws.com`のような`.amazonaws.com`系のURLは存在しない。正しくは`bedrock-mantle.<region>.api.aws`。
- **API keyの有効期限**: 短期キーは発行から12時間程度で失効し、`Bearer Token has expired`というエラーになる。期限切れかどうかは、まず新しいキーを発行して切り分ける。
