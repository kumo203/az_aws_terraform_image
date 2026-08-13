# Bedrock Mantle authenticates via a bearer token, not IAM SigV4 (see
# aws_tf/README.md), so this dedicated IAM user exists only to hold the
# service-specific credential that becomes that bearer token. No human ever
# generates or copies this key by hand — the closest AWS equivalent to
# az_tf's APIM managed-identity token acquisition (dynamic, but here static
# and auto-rotatable via credential_age_days instead of per-request).
resource "aws_iam_user" "mantle_gateway" {
  name = "${var.resource_prefix}-${local.name_suffix}-mantle-gw"
}

# Confirmed via a real 403 from bedrock-mantle: calls are authorized by
# bedrock-mantle:CreateInference on the project resource, a separate action
# namespace from bedrock:* (the classic Bedrock control/data-plane actions
# don't cover it at all). "default" is the only project this account has;
# see aws_tf/README.md "遭遇した詰まりどころ".
resource "aws_iam_user_policy" "mantle_gateway" {
  name = "bedrock-mantle-access"
  user = aws_iam_user.mantle_gateway.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = "bedrock-mantle:CreateInference"
        Resource = "arn:aws:bedrock-mantle:${var.region}:${data.aws_caller_identity.current.account_id}:project/default"
      },
      {
        # This is the same "Action=CallWithBearerToken" seen encoded inside a
        # short-term Bedrock API key's presigned URL — it authorizes the
        # bearer-token exchange itself, separately from the inference call
        # above. AWS's error for this one names Resource "*", not the
        # project ARN, so it is not project-scoped.
        Effect   = "Allow"
        Action   = "bedrock-mantle:CallWithBearerToken"
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
