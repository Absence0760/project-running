# Per-env web stack.
#
# Used by `infra/envs/<env>/main.tf`. Creates everything for one
# environment: S3 bucket (private, OAC-fronted), CloudFront
# distribution with two behaviours (default → S3, /api/coach/* →
# Lambda Function URL), the coach Lambda with response streaming, the
# per-env KMS key + alias used to encrypt secrets, the sops-decrypted
# Lambda env, and the Route 53 ALIAS records pointing at CloudFront.
#
# CloudWatch alarms live in `alarms.tf`.

locals {
  resource_prefix = "runonward-web-${var.env}"

  # If the sops file exists at apply time, decrypt it and merge into
  # the Lambda env. On first apply (before the user has encoded
  # anything against the env's KMS key), `secrets_file = null` and the
  # secrets map is empty — the Lambda boots but `/api/coach` returns
  # 503 because ANTHROPIC_API_KEY isn't set.
  has_secrets = var.secrets_file != null && fileexists(var.secrets_file)

  base_lambda_env = merge(
    {
      PUBLIC_SUPABASE_URL      = var.public_supabase_url
      PUBLIC_SUPABASE_ANON_KEY = var.public_supabase_anon_key
    },
    var.extra_lambda_env,
  )

  lambda_env = merge(
    local.base_lambda_env,
    local.has_secrets ? data.sops_file.secrets[0].data : {},
  )
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

data "sops_file" "secrets" {
  count       = local.has_secrets ? 1 : 0
  source_file = var.secrets_file
}

# Placeholder zip — used until CI's first `aws lambda update-function-
# code` replaces the code with the real bundle from
# `apps/web/lambda/coach/build.mjs`. After that, `ignore_changes` on
# the function keeps Terraform from reverting the deployed bundle.
data "archive_file" "placeholder" {
  type        = "zip"
  source_dir  = "${path.module}/placeholder"
  output_path = "${path.module}/placeholder/.placeholder.zip"
}

locals {
  effective_zip_path = var.lambda_zip_path != null ? var.lambda_zip_path : data.archive_file.placeholder.output_path
}

# ──────────────────────────── KMS key for sops ────────────────────────────

# Explicit key policy. The AWS-default policy grants the account root
# all KMS actions, which means anyone with `AdministratorAccess`
# through Identity Center could decrypt sops-encrypted secrets via
# the console — defeating the workflow-driven access posture.
#
# This policy:
#   - Lets the account root manage the key (revoke / re-grant), but
#     not call Decrypt directly without going through a delegated
#     principal.
#   - Lets the Lambda execution role call Decrypt at cold-start
#     (sops in the deployment env decrypts secrets.enc.yaml into the
#     Lambda environment).
#   - Lets the GitHub OIDC deploy role call Decrypt at terraform-apply
#     time so `data.sops_file` resolves the encrypted .yaml.
data "aws_iam_policy_document" "kms_secrets" {
  statement {
    sid    = "AllowKeyAdministrationByAccountRoot"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = [
      "kms:Create*",
      "kms:Describe*",
      "kms:Enable*",
      "kms:List*",
      "kms:Put*",
      "kms:Update*",
      "kms:Revoke*",
      "kms:Disable*",
      "kms:Get*",
      "kms:Delete*",
      "kms:TagResource",
      "kms:UntagResource",
      "kms:ScheduleKeyDeletion",
      "kms:CancelKeyDeletion",
    ]
    resources = ["*"]
  }
  statement {
    sid    = "AllowLambdaAndDeployRolesToDecrypt"
    effect = "Allow"
    principals {
      type = "AWS"
      identifiers = compact([
        # Lambda execution role — created below in this stack as
        # `${prefix}-coach-lambda`. The ARN is built deterministically
        # from the resource_prefix to avoid a key→role→key reference
        # cycle. Audit pass 3 caught a name mismatch (was `-lambda`,
        # actual role is `-coach-lambda`); keep these in lockstep.
        "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.resource_prefix}-coach-lambda",
        # Deploy role(s) that need to decrypt at terraform-apply time.
        # Optional — empty list means deploys decrypt out-of-band.
        var.kms_decrypt_principal_arn,
      ])
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:GenerateDataKey",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "secrets" {
  description             = "Encrypts sops secrets for runonward-web-${var.env}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secrets.json
  tags                    = var.tags

  # Losing this key during a careless `terraform destroy` makes every
  # secrets.enc.yaml for the env permanently undecryptable. The
  # 30-day deletion window doesn't help when Terraform is the thing
  # initiating the destroy — prevent_destroy forces a manual
  # `terraform state rm` step before deletion.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "secrets" {
  name          = "alias/${local.resource_prefix}-secrets"
  target_key_id = aws_kms_key.secrets.key_id
}

# ──────────────────────────── S3 bucket (static site) ────────────────────────────

# Trivy AWS-0089 (S3 access logging) and AWS-0132 (S3 CMK encryption)
# are suppressed for this bucket in .trivyignore at the repo root.
# Rationale: contents are intentionally public (static SvelteKit
# build), CloudFront OAC blocks direct S3 GETs, deploy writes are
# in CloudTrail. AES256 is sufficient for an asset designed to be
# served anonymously.
resource "aws_s3_bucket" "site" {
  bucket        = "${local.resource_prefix}-site"
  force_destroy = false
  tags          = var.tags

  # `terraform destroy` on a non-empty bucket already errors thanks
  # to force_destroy=false, but a fresh `aws s3 rm --recursive`
  # followed by destroy would silently take the bucket. prevent_destroy
  # forces a manual `terraform state rm` step before deletion is
  # possible from Terraform.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "site" {
  bucket                  = aws_s3_bucket.site.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "site" {
  bucket = aws_s3_bucket.site.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "site" {
  bucket = aws_s3_bucket.site.id
  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = 30
    }
  }
  # Sweep partial uploads abandoned by interrupted CI runs / aborted
  # browser uploads. Each pending multipart costs $0.005/GB/month
  # indefinitely; without this rule, broken deploys leak storage
  # forever.
  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

resource "aws_s3_bucket_policy" "site" {
  bucket = aws_s3_bucket.site.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "AllowCloudFrontReadViaOAC"
      Effect    = "Allow"
      Principal = { Service = "cloudfront.amazonaws.com" }
      Action    = "s3:GetObject"
      Resource  = "${aws_s3_bucket.site.arn}/*"
      Condition = {
        StringEquals = {
          "AWS:SourceArn" = aws_cloudfront_distribution.this.arn
        }
      }
    }]
  })
}

# ──────────────────────────── Coach Lambda ────────────────────────────

resource "aws_iam_role" "lambda" {
  name = "${local.resource_prefix}-coach-lambda"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# X-Ray write permissions for the tracing_config on aws_lambda_function.coach.
# The managed policy grants PutTraceSegments + PutTelemetryRecords only.
resource "aws_iam_role_policy_attachment" "lambda_xray" {
  role       = aws_iam_role.lambda.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

resource "aws_cloudwatch_log_group" "lambda" {
  name              = "/aws/lambda/${local.resource_prefix}-coach"
  retention_in_days = 30
  # Reuse the same CMK that already encrypts the lambda env vars.
  # KMS rotation + access policy are managed in one place; the log
  # group only contains coach request traces, which can carry the
  # same secrecy class as the env vars themselves.
  kms_key_id = aws_kms_key.secrets.arn
  tags       = var.tags
}

resource "aws_lambda_function" "coach" {
  function_name = "${local.resource_prefix}-coach"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  # Node 24 (current Active LTS). Must be 22+: @supabase/realtime-js
  # >=2.105 needs native WebSocket support, which only landed in Node
  # 22. The coach handler calls createClient() per request; on Node
  # 20 it would crash at construction with "Node.js 20 detected
  # without native WebSocket support". Bumping the runtime here also
  # requires updating the esbuild target in apps/web/lambda/coach/
  # build.mjs to match.
  runtime                        = "nodejs24.x"
  architectures                  = ["arm64"]
  memory_size                    = 1024
  timeout                        = 30
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  filename         = local.effective_zip_path
  source_code_hash = filebase64sha256(local.effective_zip_path)

  publish = true

  environment {
    variables = local.lambda_env
  }

  # X-Ray tracing — captures the upstream Anthropic call duration
  # + the supabase auth lookup as segments alongside the standard
  # Init / Invocation phases. Cost is ~$0.000005 per traced
  # request which is negligible at coach's volume.
  tracing_config {
    mode = "Active"
  }

  tags = var.tags

  # CI updates the code on every web@* tag via `aws lambda update-
  # function-code`. We don't want Terraform to fight CI by reverting
  # to var.lambda_zip_path — once the function exists, code changes
  # are CI's job, infra changes (env vars, role, alarms, distribution)
  # are Terraform's job. Same for the bumped version that CI publishes.
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
      qualified_arn,
      version,
    ]
  }

  depends_on = [aws_cloudwatch_log_group.lambda]
}

resource "aws_lambda_alias" "live" {
  name             = "live"
  function_name    = aws_lambda_function.coach.function_name
  function_version = aws_lambda_function.coach.version

  # CI retargets this alias on every deploy. Same rationale as
  # ignore_changes on the function itself.
  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_lambda_function_url" "coach" {
  function_name      = aws_lambda_function.coach.function_name
  qualifier          = aws_lambda_alias.live.name
  authorization_type = "AWS_IAM"
  invoke_mode        = "RESPONSE_STREAM"

  cors {
    allow_origins = ["https://${var.domain_name}"]
    allow_methods = ["POST"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 3600
  }
}

# CloudFront → Lambda Function URL OAC (AWS announced April 2024).
# CloudFront sigv4-signs every request with the role granted in
# `aws_lambda_permission.cloudfront_invoke` below; without that signed
# header the Function URL rejects with 403. Combined with
# `authorization_type = "AWS_IAM"` on the Function URL itself, this
# means anyone who learns the .lambda-url.* hostname can't bypass
# CloudFront — a curl directly to the URL gets 403.
resource "aws_cloudfront_origin_access_control" "lambda" {
  name                              = "${local.resource_prefix}-lambda-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_lambda_permission" "cloudfront_invoke" {
  statement_id           = "AllowCloudFrontInvoke"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.coach.function_name
  qualifier              = aws_lambda_alias.live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this.arn
  function_url_auth_type = "AWS_IAM"

  # Pair with create_before_destroy on any future qualifier rotation —
  # avoids a brief window where the new permission isn't attached yet
  # but the old one has already been deleted, which would 403 every
  # in-flight CloudFront → Lambda call.
  lifecycle {
    create_before_destroy = true
  }
}

# ──────────────────────────── CloudFront ────────────────────────────

resource "aws_cloudfront_origin_access_control" "site" {
  name                              = "${local.resource_prefix}-site-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_response_headers_policy" "security" {
  name    = "${local.resource_prefix}-security"
  comment = "Security headers for ${var.domain_name}"

  security_headers_config {
    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      preload                    = true
      override                   = true
    }
    content_type_options {
      override = true
    }
    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }
    frame_options {
      frame_option = "DENY"
      override     = true
    }
    # CSP — the app loads MapTiler tiles, calls Supabase, streams from
    # itself. `unsafe-eval` was dropped in this pass: SvelteKit's
    # production build does not eval; it was carried forward from a
    # development-stage policy. `unsafe-inline` on script-src remains
    # because the static build inlines the page-data hydration script;
    # nonce-based tightening is the next step but requires a dynamic
    # response path we don't have on adapter-static.
    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'self'",
        # OAuth avatar origins (lh3.googleusercontent.com from Google
        # sign-in, Apple's id.apple.com variants) plus Supabase
        # Storage signed URLs (run-photos bucket bytes) plus MapTiler
        # tile previews. `data:image/svg+xml` covers the SvelteKit
        # icon-component inline SVGs without enabling
        # `data:text/html` (which a future {@html} regression could
        # smuggle through into a navigation context).
        "img-src 'self' data:image/svg+xml https://*.supabase.co https://*.maptiler.com https://lh3.googleusercontent.com https://*.appleid.apple.com",
        "script-src 'self' 'unsafe-inline'",
        "style-src 'self' 'unsafe-inline'",
        "font-src 'self' data:",
        # `connect-src` covers fetch / XHR / EventSource / WebSocket —
        # everything the browser sends OUT. `*.ingest.sentry.io` is
        # where @sentry/sveltekit's browser SDK posts errors; without
        # it errors are silently CSP-blocked. `*.supabase.{co,io}`
        # covers REST + Realtime + Storage; `*.maptiler.com` covers
        # tile fetches.
        # Drop the unused .supabase.io alias — the project is on
        # *.supabase.co. Wildcards across two TLDs widen the
        # exfiltration surface for no win.
        "connect-src 'self' https://*.supabase.co https://api.runonward.com https://*.maptiler.com https://*.ingest.sentry.io",
        "worker-src 'self' blob:",
        "manifest-src 'self'",
        "object-src 'none'",
        "base-uri 'self'",
        "form-action 'self'",
        "frame-ancestors 'none'",
      ])
      override = true
    }
  }

  # Disable powerful browser APIs the app doesn't use — closes
  # opportunistic-XSS payloads from reaching the device sensor /
  # autofill / payment / clipboard surfaces. CloudFront only models
  # this as a custom header, not as part of security_headers_config.
  custom_headers_config {
    items {
      header = "Permissions-Policy"
      # geolocation is allowed for the first-party origin only —
      # RouteBuilder, PrivacyZonePicker, RouteExplorer, and
      # /routes/new all call navigator.geolocation. Everything else
      # the app doesn't use stays denied. The `interest-cohort=()`
      # directive is the FLoC original; the rest disable the Privacy
      # Sandbox successors (Topics API, Protected Audience,
      # Attribution Reporting, Private Aggregation). Without these,
      # an XSS-injected `document.browsingTopics()` call would
      # execute and exfiltrate the user's interest cohort.
      value    = "accelerometer=(), attribution-reporting=(), browsing-topics=(), camera=(), geolocation=(self), gyroscope=(), interest-cohort=(), join-ad-interest-group=(), magnetometer=(), microphone=(), payment=(), private-aggregation=(), run-ad-auction=(), usb=()"
      override = true
    }
  }
}

resource "aws_cloudfront_cache_policy" "static" {
  name        = "${local.resource_prefix}-static"
  comment     = "Static assets — cache aggressively"
  default_ttl = 86400
  max_ttl     = 31536000
  min_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}

resource "aws_cloudfront_cache_policy" "lambda_passthrough" {
  name        = "${local.resource_prefix}-lambda-passthrough"
  comment     = "Coach endpoint — disables caching, streams responses"
  default_ttl = 0
  max_ttl     = 0
  min_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false
    cookies_config { cookie_behavior = "all" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "all" }
  }
}

resource "aws_cloudfront_origin_request_policy" "lambda" {
  name = "${local.resource_prefix}-lambda-origin"
  cookies_config { cookie_behavior = "all" }
  query_strings_config { query_string_behavior = "all" }
  # Explicit allowlist excluding `Authorization`: when Lambda OAC is
  # in use, CloudFront sigv4-signs every origin request in the
  # `Authorization` header. Forwarding the viewer's `Authorization`
  # collides with that signature, fails OAC, and 403s. The user's
  # Supabase JWT is therefore carried in `X-Supabase-Authorization`
  # (read by both the Lambda handler and the SvelteKit dev wrapper).
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = [
        "content-type",
        "accept",
        "accept-encoding",
        "x-supabase-authorization",
      ]
    }
  }
}

# Trivy AWS-0010 (CloudFront access logging) is suppressed in
# .trivyignore at the repo root. Rationale: real-time CloudWatch
# metrics + per-Lambda alarms in alarms.tf already cover the
# operational signals. Per-IP audit trails aren't a requirement
# today (anonymous viewers are intentional).
resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.resource_prefix} — SvelteKit static + /api/coach"
  default_root_object = "index.html"
  http_version        = "http2and3"
  price_class         = "PriceClass_100"
  aliases             = concat([var.domain_name], var.aliases)
  tags                = var.tags
  web_acl_id          = var.waf_enabled ? aws_wafv2_web_acl.coach[0].arn : null

  origin {
    origin_id                = "s3-site"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.site.id
  }

  origin {
    origin_id                = "lambda-coach"
    domain_name              = replace(aws_lambda_function_url.coach.function_url, "/^https?:\\/\\/([^/]+)\\/?.*$/", "$1")
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  default_cache_behavior {
    target_origin_id           = "s3-site"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.static.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }

  ordered_cache_behavior {
    path_pattern               = "/api/coach*"
    target_origin_id           = "lambda-coach"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = false
    cache_policy_id            = aws_cloudfront_cache_policy.lambda_passthrough.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.lambda.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id
  }

  # SPA fallback — SvelteKit static fallback is index.html on 404.
  custom_error_response {
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.acm_certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ──────────────────────────── DNS records ────────────────────────────

resource "aws_route53_record" "primary" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "primary_aaaa" {
  zone_id = var.route53_zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "aliases_a" {
  for_each = toset(var.aliases)

  zone_id = var.route53_zone_id
  name    = each.value
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "aliases_aaaa" {
  for_each = toset(var.aliases)

  zone_id = var.route53_zone_id
  name    = each.value
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
