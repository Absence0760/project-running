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
#
# ── Trust-policy contract that has to stay in sync with the workflow ──
#
# These trust policies match GitHub's `:sub` claim shape for the
# `push` event family ONLY:
#
#   refs/tags/web@*          push (tag)         → assumes deploy_prod
#   refs/heads/main          push (branch)      → assumes deploy_preview
#
# `pull_request` events have a different `:sub` shape
# (`pull_request:...`) — they CANNOT assume either role, which is
# correct: a fork PR must never be able to deploy. `workflow_dispatch`
# events from the configured branch share the `refs/heads/main`
# shape — so a manual run from `main` would assume deploy_preview.
# That's currently fine because the only trigger in
# `.github/workflows/release-web.yml` is `on: push: { tags, branches:
# [main] }`. If you ever add `workflow_dispatch` or any other trigger,
# revisit these StringLike conditions or scope per-trigger via
# environments.

# ── CloudFrontInvalidate scoping caveat ──
#
# `cloudfront:CreateInvalidation` is granted on `Resource: "*"` in
# both deploy roles below because:
#   1. The CloudFront distribution doesn't exist when this stack is
#      applied (`envs/<env>` apply happens after `github-oidc`).
#      Threading the distribution ARN as a var creates a circular
#      dependency between the two stacks.
#   2. CloudFront has no resource-level permissions for invalidation
#      regardless — IAM ARNs aren't matched against distribution IDs
#      for this specific action; AWS only enforces account-level
#      isolation here.
# Net effect: a leaked prod token can invalidate the preview
# distribution and vice versa. Blast radius is "stale-cache flush",
# not data exposure. If we ever multi-tenant a single AWS account
# under different trust boundaries, split this into per-distribution
# managed policies and accept the apply-ordering tax.

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

# Baseline tags applied to every IAM resource in this stack. Caller
# overrides via `var.tags`; default keys ensure cost-allocation +
# stack ownership are visible without configuration.
locals {
  oidc_tags = merge(
    {
      Project   = "run-app"
      Stack     = "github-oidc"
      ManagedBy = "terraform"
    },
    var.tags,
  )
}

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
  tags = local.oidc_tags
}

# ─────────────────── Deploy role: prod ───────────────────

resource "aws_iam_role" "deploy_prod" {
  name = "threkir-web-deploy-prod"
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
  tags = merge(local.oidc_tags, { Environment = "prod" })
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
          "arn:aws:s3:::threkir-web-prod-site",
          "arn:aws:s3:::threkir-web-prod-site/*",
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
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-prod-coach*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-prod-generate-route*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-prod-share-run*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-prod-share-route*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-prod-share-recap*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-prod-share-badge*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-prod-share-entity*",
        ]
      },
    ]
  })
}

# ─────────────────── Deploy role: preview ───────────────────

resource "aws_iam_role" "deploy_preview" {
  name = "threkir-web-deploy-preview"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = aws_iam_openid_connect_provider.github.arn }
      Action    = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        # Pin to literal `refs/heads/main` — no wildcard, so
        # StringEquals expresses the intent precisely (preview can
        # only assume from the main-branch workflow).
        StringEquals = {
          "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:ref:refs/heads/main"
        }
      }
    }]
  })
  tags = merge(local.oidc_tags, { Environment = "preview" })
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
          "arn:aws:s3:::threkir-web-preview-site",
          "arn:aws:s3:::threkir-web-preview-site/*",
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
        Resource = [
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-preview-coach*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-preview-generate-route*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-preview-share-run*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-preview-share-route*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-preview-share-recap*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-preview-share-badge*",
          "arn:aws:lambda:${var.aws_region}:${data.aws_caller_identity.current.account_id}:function:threkir-web-preview-share-entity*",
        ]
      },
    ]
  })
}
