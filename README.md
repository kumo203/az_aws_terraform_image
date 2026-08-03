# Terraform + Azure CLI + AWS CLI + Claude Code + Codex CLI Docker Image

## 概要

公式 Terraform イメージ（Alpine）をベースにすると AWS CLI v2 が公式サポートされていないため、
マルチステージビルドで Terraform バイナリだけを抽出し、Debian slim 上に各 CLI を正規インストールしたイメージ。

## 収録ツール（確認済みバージョン）

| ツール | バージョン |
|---|---|
| Terraform | v1.15.8 |
| Azure CLI | 2.88.0 |
| AWS CLI | v2.36.14 |
| Node.js | v22.23.2 |
| Claude Code | 2.1.220 |
| Codex CLI | 0.146.0 |

## マルチステージビルドの仕組み

```
Stage 1: hashicorp/terraform:latest (Alpine)
         └── /bin/terraform だけ抽出

Stage 2: debian:bookworm-slim (最終イメージ)
         ├── /usr/local/bin/terraform  ← Stage 1 からコピー
         ├── az     (Microsoft 公式スクリプト)
         ├── aws    (公式 zip インストーラー)
         ├── node   (NodeSource 22.x LTS)
         ├── claude (npm @anthropic-ai/claude-code)
         └── codex  (npm @openai/codex)
```

Terraform は単一バイナリなので Alpine から取り出してそのまま Debian で動く。

## ビルド

```bash
docker build -t tf-azure-aws-ai .
```

## 使い方

### バージョン確認

```bash
docker run --rm tf-azure-aws-ai terraform version
docker run --rm tf-azure-aws-ai az version
docker run --rm tf-azure-aws-ai aws --version
docker run --rm tf-azure-aws-ai claude --version
docker run --rm tf-azure-aws-ai codex --version
```

### 認証情報の永続化

各 CLI は `/root/` 配下に認証情報を保存する。名前付きボリュームで永続化することで、ログインを一度で済ませられる。

```bash
# 初回：コンテナ内で各 CLI の認証を済ませる
docker run --rm -it -v root-map:/root tf-azure-aws-ai

# 2回目以降：認証不要
docker run --rm -it -v root-map:/root tf-azure-aws-ai
```

ツールごとに分けたい場合：

```bash
docker run --rm -it \
  -v azure-creds:/root/.azure \
  -v aws-creds:/root/.aws \
  -v claude-config:/root/.claude \
  tf-azure-aws-ai
```

### API キーを渡して起動

```bash
docker run --rm -it \
  -e ANTHROPIC_API_KEY=your_key \
  -e OPENAI_API_KEY=your_key \
  -v root-map:/root \
  tf-azure-aws-ai
```

## 注意事項

- **Azure CLI のトークンは有効期限あり**（数時間〜数日）。期限切れ後は `az login` が必要。長期運用にはサービスプリンシパル（`az login --service-principal`）を推奨。
- **AWS CLI のアクセスキー**は明示的にローテーションしない限り永続する。
- **アーキテクチャ**: amd64 のみ対応。arm64 対応には `buildx` + `TARGETARCH` 分岐が必要。
- **Terraform バージョン固定**: `FROM hashicorp/terraform:1.9.5` のようにタグを指定すると再現性が上がる。
