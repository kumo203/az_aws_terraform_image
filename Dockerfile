# syntax=docker/dockerfile:1

# Stage 1: Extract Terraform binary from the official Alpine-based image
FROM hashicorp/terraform:latest AS terraform

# Stage 2: Final image on Debian slim for full Azure CLI / AWS CLI v2 support
FROM debian:bookworm-slim

COPY --from=terraform /bin/terraform /usr/local/bin/terraform

# Base dependencies required by subsequent installers
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    gnupg \
    ca-certificates \
    unzip \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Azure CLI (Microsoft official script adds apt repo and installs azure-cli)
RUN curl -sL https://aka.ms/InstallAzureCLIDeb | bash \
    && rm -rf /var/lib/apt/lists/*

# AWS CLI v2
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip \
    && unzip /tmp/awscliv2.zip -d /tmp \
    && /tmp/aws/install \
    && rm -rf /tmp/awscliv2.zip /tmp/aws

# Node.js 22.x LTS (required by Claude Code CLI and Codex CLI)
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI and OpenAI Codex CLI
RUN npm install -g @anthropic-ai/claude-code @openai/codex

# GitHub CLI (gh)
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg -o /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["/bin/bash"]
