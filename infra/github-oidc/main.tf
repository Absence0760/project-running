# GitHub OIDC provider + per-env deploy roles.
#
# GitHub Actions assume these roles via OIDC token exchange — no long-
# lived AWS keys in `Settings → Secrets`. The trust policies are
# scoped per env:
#
#   prod    only assumable from a tag matching refs/tags/web@*
#   preview only assumable from a push to refs/heads/main
#
# Permissions: each role can sync the env's S3 bucket, invalidate the
# env's CloudFront distribution, and update the env's Lambda. Nothing
# else.

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# ─────────────────── OIDC provider ───────────────────

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
  # Thumbprints are GitHub's; AWS validates them inline now, but the
  # field is still required by the IAM API.
  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd",
  ]
  tags = var.tags
}

# ─────────────────── Deploy role: prod ───────────────────

resource "aws_iam_role" "deploy_prod" {
  name = "runonward-web-deploy-prod"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/tags/web@*"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "deploy_prod" {
  role = aws_iam_role.deploy_prod.id
  name = "deploy-permissions"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3SyncSiteBucket"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::runonward-web-prod-site",
          "arn:aws:s3:::runonward-web-prod-site/*",
        ]
      },
      {
        Sid      = "CloudFrontInvalidate"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "*"
      },
      {
        Sid    = "LambdaUpdate"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:PublishVersion",
          "lambda:UpdateAlias",
          "lambda:GetFunction",
          "lambda:GetAlias",
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:runonward-web-prod-coach*"
      },
    ]
  })
}

# ─────────────────── Deploy role: preview ───────────────────

resource "aws_iam_role" "deploy_preview" {
  name = "runonward-web-deploy-preview"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
        }
        StringLike = {
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "deploy_preview" {
  role = aws_iam_role.deploy_preview.id
  name = "deploy-permissions"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3SyncSiteBucket"
        Effect = "Allow"
        Action = ["s3:PutObject", "s3:DeleteObject", "s3:GetObject", "s3:ListBucket"]
        Resource = [
          "arn:aws:s3:::runonward-web-preview-site",
          "arn:aws:s3:::runonward-web-preview-site/*",
        ]
      },
      {
        Sid      = "CloudFrontInvalidate"
        Effect   = "Allow"
        Action   = ["cloudfront:CreateInvalidation"]
        Resource = "*"
      },
      {
        Sid    = "LambdaUpdate"
        Effect = "Allow"
        Action = [
          "lambda:UpdateFunctionCode",
          "lambda:PublishVersion",
          "lambda:UpdateAlias",
          "lambda:GetFunction",
          "lambda:GetAlias",
        ]
        Resource = "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:runonward-web-preview-coach*"
      },
    ]
  })
}
