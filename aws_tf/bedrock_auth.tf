# Bedrock Mantle authenticates via a bearer token, not IAM SigV4 (see
# aws_tf/README.md), so this dedicated IAM user exists only to hold the
# service-specific credential that becomes that bearer token. No human ever
# generates or copies this key by hand — the closest AWS equivalent to
# az_tf's APIM managed-identity token acquisition (dynamic, but here static
# and auto-rotatable via credential_age_days instead of per-request).
resource "aws_iam_user" "mantle_gateway" {
  name = "${var.resource_prefix}-${local.name_suffix}-mantle-gw"
}

# NOTE: the exact IAM action(s) required for a Bedrock API key to actually
# call bedrock-mantle are not documented/confirmed as of writing (Mantle
# calls are authorized by the bearer token itself, not necessarily by an
# InvokeModel-style IAM action on this user). Starts broad; tighten once
# verified against a real call (see aws_tf/README.md "遭遇した詰まりどころ"
# once that verification happens).
resource "aws_iam_user_policy" "mantle_gateway" {
  name = "bedrock-mantle-access"
  user = aws_iam_user.mantle_gateway.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "bedrock:*"
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_service_specific_credential" "mantle_key" {
  user_name           = aws_iam_user.mantle_gateway.name
  service_name        = "bedrock.amazonaws.com"
  credential_age_days = var.bedrock_credential_expiration_days
}

resource "aws_secretsmanager_secret" "mantle_bearer_token" {
  name = "${var.resource_prefix}-${local.name_suffix}-mantle-bearer"
}

# service_credential_secret (not service_password — that attribute is for
# CodeCommit/Keyspaces-style credentials) is exactly the string used as the
# "Bearer ..." token against bedrock-mantle (see aws_tf/README.md). The
# Lambda proxy fetches this at request time instead of having the token
# baked into its code/env.
resource "aws_secretsmanager_secret_version" "mantle_bearer_token" {
  secret_id     = aws_secretsmanager_secret.mantle_bearer_token.id
  secret_string = aws_iam_service_specific_credential.mantle_key.service_credential_secret
}
