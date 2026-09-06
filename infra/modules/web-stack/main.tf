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
  resource_prefix = "threkir-web-${var.env}"

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

  # The coach Lambda's half of the secrets file, by name. This env used to be
  # the whole decrypted map: every key the file grows for any OTHER consumer —
  # the routing engines' shared X-Engine-Key today, a payments or mail key
  # tomorrow — landed in this function's environment whether the handler reads
  # it or not, visible to anyone who can call GetFunctionConfiguration and to
  # any code-execution bug in the handler. `generate_route_lambda_env` below
  # already takes only the two keys it uses, and its comment names this env as
  # the contrast ("not the whole secret bag the coach Lambda gets"); this is
  # that same narrowing applied to the bag it was contrasting with.
  #
  # The list is the set the coach handler and its cores read out of
  # process.env, minus the two PUBLIC_ values that come from module vars. A key
  # the coach needs and this list omits is an unset env, which the handler
  # already answers as a tagged 503 rather than as a silent degrade — the
  # fail-closed direction.
  coach_secret_keys = [
    "ANTHROPIC_API_KEY",
    "SUPABASE_SECRET_KEY",
    "COACH_PROVIDER",
    "OPENAI_API_KEY",
    "OPENAI_BASE_URL",
    "OPENAI_MODEL",
  ]

  lambda_env = merge(
    local.base_lambda_env,
    local.has_secrets ? { for k, v in data.sops_file.secrets[0].data : k => v if contains(local.coach_secret_keys, k) } : {},
  )

  # share-run Lambda env. Doesn't need any sops-decrypted secrets —
  # every read is via the public anon key against anon-readable
  # views (public_runs + public_profiles). Adding PUBLIC_SITE_URL so
  # the og:url + og:image absolute URLs are env-specific.
  share_run_lambda_env = merge(
    {
      PUBLIC_SUPABASE_URL      = var.public_supabase_url
      PUBLIC_SUPABASE_ANON_KEY = var.public_supabase_anon_key
      PUBLIC_SITE_URL          = var.public_site_url
    },
  )

  # share-route Lambda env. Same shape + posture as the share-run env
  # (anon key against the anon-readable public_routes view + the
  # clip_track_for_user RPC; PUBLIC_SITE_URL for env-specific absolute
  # og:url / og:image / canonical / JSON-LD URLs). Kept as its own
  # local so the two share surfaces stay independently owned.
  share_route_lambda_env = merge(
    {
      PUBLIC_SUPABASE_URL      = var.public_supabase_url
      PUBLIC_SUPABASE_ANON_KEY = var.public_supabase_anon_key
      PUBLIC_SITE_URL          = var.public_site_url
    },
  )

  # share-recap Lambda env. Same shape + posture as the share-run /
  # share-route envs (anon key against the anon-readable public_recaps
  # row; PUBLIC_SITE_URL for env-specific absolute og:url / og:image /
  # canonical URLs). The recap snapshot is aggregate-only (no track),
  # so no clip RPC is needed. Kept as its own local so the three share
  # surfaces stay independently owned.
  share_recap_lambda_env = merge(
    {
      PUBLIC_SUPABASE_URL      = var.public_supabase_url
      PUBLIC_SUPABASE_ANON_KEY = var.public_supabase_anon_key
      PUBLIC_SITE_URL          = var.public_site_url
    },
  )

  # share-badge Lambda env. Same shape + posture as the share-run /
  # share-route / share-recap envs (anon key against the anon-readable
  # public, milestone-safe badge columns; PUBLIC_SITE_URL for
  # env-specific absolute og:url / og:image / canonical URLs). A badge
  # card is a numeric milestone + a date, so no clip RPC is needed. Kept
  # as its own local so the four share surfaces stay independently owned.
  share_badge_lambda_env = merge(
    {
      PUBLIC_SUPABASE_URL      = var.public_supabase_url
      PUBLIC_SUPABASE_ANON_KEY = var.public_supabase_anon_key
      PUBLIC_SITE_URL          = var.public_site_url
    },
  )

  # share-entity Lambda env. One HTML-only Lambda serving the six public
  # /share/{event,profile,club,race,session,workout} entity paths; same
  # anon-key posture
  # as the other share Lambdas (reads only anon-readable public rows;
  # PUBLIC_SITE_URL for env-specific absolute canonical / og:url URLs).
  share_entity_lambda_env = merge(
    {
      PUBLIC_SUPABASE_URL      = var.public_supabase_url
      PUBLIC_SUPABASE_ANON_KEY = var.public_supabase_anon_key
      PUBLIC_SITE_URL          = var.public_site_url
    },
  )

  # generate-route Lambda env. Engine URLs (GRAPH_CYCLE_URL + GRAPHHOPPER_URL)
  # are non-secret internal URLs passed as plain Terraform vars; an empty string
  # is omitted so the handler sees that env unset and simply skips that engine
  # (GRAPH_CYCLE_URL unset → skip graph-cycle, fall to round_trip; both unset →
  # 501 and the client falls back to the OSRM heuristic). The matching API keys
  # (GRAPH_CYCLE_API_KEY + GRAPHHOPPER_API_KEY) are the shared secrets the handler
  # sends as X-Engine-Key to clear each engine's guard — pulled from the sops file
  # (ONLY those keys, not the whole secret bag the coach Lambda gets). Absent in
  # sops → no header sent; if the engine's guard is active it 403s, the handler
  # falls back, and (for round_trip) the engine-unreachable alarm fires. The
  # Supabase pair backs the Pro gate's is_pro() check (decisions §204) — both
  # are public client values, not secrets; if they're ever absent the handler
  # fails the tier check closed (500) rather than skipping the gate.
  generate_route_lambda_env = merge(
    {
      PUBLIC_SUPABASE_URL      = var.public_supabase_url
      PUBLIC_SUPABASE_ANON_KEY = var.public_supabase_anon_key
    },
    var.graph_cycle_url != "" ? { GRAPH_CYCLE_URL = var.graph_cycle_url } : {},
    var.graphhopper_url != "" ? { GRAPHHOPPER_URL = var.graphhopper_url } : {},
    local.has_secrets ? { for k, v in data.sops_file.secrets[0].data : k => v if k == "GRAPHHOPPER_API_KEY" || k == "GRAPH_CYCLE_API_KEY" } : {},
  )

  # osrm-proxy Lambda env. OSRM_URL is a non-secret internal engine URL passed
  # as a plain Terraform var (same posture as GRAPHHOPPER_URL — issue #198: the
  # browser must never see it); an empty string is omitted so the handler sees
  # the env unset and answers 501 (the route builder degrades to straight-line
  # segments). The Supabase pair backs the auth gate's auth.getUser check —
  # public client values, not secrets; absent → the handler fails the gate
  # closed (500) rather than serving anonymously.
  osrm_proxy_lambda_env = merge(
    {
      PUBLIC_SUPABASE_URL      = var.public_supabase_url
      PUBLIC_SUPABASE_ANON_KEY = var.public_supabase_anon_key
    },
    var.osrm_url != "" ? { OSRM_URL = var.osrm_url } : {},
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
  effective_zip_path                = var.lambda_zip_path != null ? var.lambda_zip_path : data.archive_file.placeholder.output_path
  effective_share_run_zip_path      = var.share_run_lambda_zip_path != null ? var.share_run_lambda_zip_path : data.archive_file.placeholder.output_path
  effective_share_route_zip_path    = var.share_route_lambda_zip_path != null ? var.share_route_lambda_zip_path : data.archive_file.placeholder.output_path
  effective_share_recap_zip_path    = var.share_recap_lambda_zip_path != null ? var.share_recap_lambda_zip_path : data.archive_file.placeholder.output_path
  effective_share_badge_zip_path    = var.share_badge_lambda_zip_path != null ? var.share_badge_lambda_zip_path : data.archive_file.placeholder.output_path
  effective_share_entity_zip_path   = var.share_entity_lambda_zip_path != null ? var.share_entity_lambda_zip_path : data.archive_file.placeholder.output_path
  effective_generate_route_zip_path = var.generate_route_lambda_zip_path != null ? var.generate_route_lambda_zip_path : data.archive_file.placeholder.output_path
  effective_osrm_proxy_zip_path     = var.osrm_proxy_lambda_zip_path != null ? var.osrm_proxy_lambda_zip_path : data.archive_file.placeholder.output_path
}

# ──────────────────────────── KMS key for sops ────────────────────────────

# Explicit key policy, enumerating four statements rather than taking the
# AWS default.
#
# READ THE POSTURE HONESTLY: an Identity Center principal with
# `AdministratorAccess` CAN decrypt this env's sops secrets. The
# `AllowOperatorSopsUseViaIamPolicies` statement below delegates
# Encrypt/Decrypt/GenerateDataKey to the account root, which means
# "whatever this account's own IAM policies allow" — and an admin's do.
# That is deliberate and load-bearing, not an oversight: `sops <file>`,
# `sops --set` (bin/secret-set.sh) and `sops updatekeys`
# (bin/key-rotate.sh) all decrypt before they re-encrypt, so an operator
# with no Decrypt has no way to rotate a secret. This comment used to
# claim the opposite — that root could manage the key "but not call
# Decrypt directly" — which was true only for the two weeks before that
# statement was added, and is the sentence a reader would otherwise
# carry into a threat model. The residual risk (any account admin can
# read prod secrets) is tracked in docs/product/followups.md; narrowing
# it means a dedicated operator principal, not deleting the statement.
#
# What the enumeration DOES buy over the AWS default: the default grants
# root every KMS action including `kms:*` on future ones, while this
# lists them, so a new privileged action is a deliberate edit; and
# CloudWatch Logs + the delegated roles are each scoped to what they
# need rather than inheriting the whole surface.
#
# The four statements:
#   - Account root may ADMINISTER the key (create / describe / enable /
#     tag / schedule deletion). No data-plane action here.
#   - The CloudWatch Logs service principal may use the key for the
#     Lambda log groups, scoped by encryption context to this env's
#     `/aws/lambda/<prefix>-*` groups.
#   - Account root may Encrypt/Decrypt/GenerateDataKey via IAM policies,
#     for the local operator sops flows described above.
#   - Decrypt + DescribeKey for the Lambda execution role. NEITHER
#     principal in that statement has ever been shown to exercise it,
#     and the sentence this comment used to carry — that the execution
#     role "decrypts the sops env at cold-start" — is not what happens:
#     data.sops_file decrypts at APPLY time and `local.lambda_env` puts
#     the result into `environment { variables }` as plaintext, so the
#     handler reads process.env and calls no KMS API (measured: no
#     `kms` reference anywhere under apps/web/lambda/). The env vars are
#     encrypted at rest by the AWS-managed `aws/lambda` key, not by this
#     CMK — no aws_lambda_function here sets `kms_key_arn`. The deploy
#     role was removed from the statement in decisions § 1021; the
#     execution role's grant is unexercised for the same reason and is
#     filed in followups.md rather than removed, because emptying the
#     statement is a structural change and one live-configuration read
#     settles it. scripts/check_infra_iam.mjs holds both premises.
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
  # CloudWatch Logs encrypts the lambda log groups with this same CMK
  # (kms_key_id on every aws_cloudwatch_log_group below). A service
  # principal can only be authorised in the KEY policy — without this
  # statement CreateLogGroup fails with "The specified KMS key does not
  # exist or is not allowed to be used". Scoped by encryption context
  # to this env's lambda log groups.
  statement {
    sid    = "AllowCloudWatchLogsUseOfTheKey"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.region}.amazonaws.com"]
    }
    actions = [
      "kms:Encrypt*",
      "kms:Decrypt*",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:Describe*",
    ]
    resources = ["*"]
    condition {
      test     = "ArnLike"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:aws:logs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:log-group:/aws/lambda/${local.resource_prefix}-*"]
    }
  }
  # The decrypt statement below assumes sops ENCRYPTION "is a LOCAL
  # operator action run under the operator's own admin/SSO principal" —
  # but KMS only honours an IAM identity policy when the KEY policy
  # delegates the action to the account, and the root statement above
  # deliberately enumerates admin actions only (no Encrypt/DataKey).
  # Net effect before this statement: NO principal in the account could
  # ever sops-encrypt against the key, breaking bin/sops-init.sh's and
  # bin/secret-set.sh's documented flows (found 2026-07-21 while
  # backing up the Android upload keystore). Root-principal delegation
  # means "whatever this account's own IAM policies allow" — it grants
  # nothing by itself and nothing outside the account.
  statement {
    sid    = "AllowOperatorSopsUseViaIamPolicies"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
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
        # An extra principal that genuinely needs apply-time decrypt.
        # BOTH env stacks now leave this "" and `compact()` drops it: the
        # only apply that reads data.sops_file is the operator's own, under
        # a principal already covered by AllowOperatorSopsUseViaIamPolicies.
        # The Sid is historic — the statement holds one identifier now, and
        # decisions § 892 named it before § 1021 emptied the deploy half.
        var.kms_decrypt_principal_arn,
      ])
    }
    # Decrypt path ONLY — kms:GenerateDataKey is deliberately omitted
    # (audit/infra M1, least-privilege). Encryption (sops --encrypt / --set /
    # updatekeys, in sops-init / secret-set / key-rotate) is a LOCAL operator
    # action run under the operator's own admin/SSO principal, not this role.
    # This comment used to say the Lambda "decrypts the sops env at cold-start";
    # it does not — see the header above.
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
    ]
    resources = ["*"]
  }
}

resource "aws_kms_key" "secrets" {
  description             = "Encrypts sops secrets for threkir-web-${var.env}"
  deletion_window_in_days = 30
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.kms_secrets.json
  tags                    = var.tags

  # Losing this key during a careless `terraform destroy` makes the env's
  # secrets file (../infra-secrets/running/<env>.sops.yaml) permanently
  # undecryptable. The
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
  # Reuse the CMK that encrypts the sops file the env vars come OUT of.
  # (It does not encrypt the env vars themselves — no aws_lambda_function
  # in this module sets `kms_key_arn`, so Lambda holds them under the
  # AWS-managed `aws/lambda` key. This comment claimed otherwise until
  # decisions § 1021.) KMS rotation + access policy are managed in one
  # place; the log group only contains coach request traces, which can
  # carry the same secrecy class as the env vars themselves.
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
  # are Terraform's job. Only filename + source_code_hash are ignored:
  # `version`/`qualified_arn` are provider-computed (ignoring them is a
  # no-op Terraform now warns on), and the published version is tracked
  # by the alias below, which CI repoints via update-alias.
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
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
  #
  # Consequence (issue #590 defect 2, same for all eight aliases in
  # this module): an env-only `terraform apply` publishes a fresh
  # version (`publish = true`) carrying the new env, but the alias —
  # and the Function URL, which targets the alias — keeps serving the
  # old version with its FROZEN env snapshot. After any secret / env
  # rotation apply, run `bin/lambda-alias-sync.sh <env>` (or cut a
  # release) so the rotation actually reaches the serving path.
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
    # `x-supabase-authorization` is the header the client actually
    # sends (CloudFront's Lambda OAC takes the `Authorization` slot
    # for its sigv4 signature — see the comment block above the
    # `aws_lambda_function.coach` resource). Missing this header
    # silently breaks CORS preflight on any non-CloudFront origin
    # (preview deployments hit it first). Audit/coach May 2026 Low #12.
    # `x-amz-content-sha256` is the client-supplied sigv4 payload hash
    # OAC-signed POSTs require (issue #590 defect 3) — not
    # CORS-safelisted, so a cross-origin preflight must allow it too.
    allow_headers = ["authorization", "content-type", "x-supabase-authorization", "x-amz-content-sha256"]
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

# AWS's OAC-for-Lambda contract requires TWO grants: `InvokeFunctionUrl`
# above AND plain `lambda:InvokeFunction`. With only the first, the
# Function URL rejects every CloudFront-signed request with 403 BEFORE
# invocation — and the distribution's SPA error fallback rewrites that
# 403 into the shell at 200, so the surface looks healthy while the
# Lambda never runs. Direct admin sigv4 probes still succeed (operator
# identity policies carry both actions), which is why the config reviews
# as correct without this resource. Issue #590; empirically proven
# 2026-07-21 by a temporary additive grant on share-run.
# `function_url_auth_type` is only valid on InvokeFunctionUrl grants, so
# it's omitted here.
resource "aws_lambda_permission" "cloudfront_invoke_function" {
  statement_id  = "AllowCloudFrontInvokeFunction"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.coach.function_name
  qualifier     = aws_lambda_alias.live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this.arn

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Share-run Lambda (persona-hunt Casual #4 + round-5 very-social) ───
#
# Per-request SSR handler for /share/run/<id> (HTML) + /og/run/<id>.png
# (PNG). Pre-fix, both routes were prerendered at build time via
# adapter-static; any public run created post-build served the SPA-
# shell fallback `<head>` and a 404 og:image, so Slack / FB / X /
# LinkedIn unfurls of a brand-new run showed the homepage card with a
# broken image. This Lambda fetches the run + display name at request
# time so every URL gets the right OG head AND a rendered image,
# regardless of build cadence. The PNG path falls back to a generic
# branded card (HTTP 200) for private / deleted runs so an unfurl
# never breaks. See apps/web/lambda/share-run/README.md for the
# bundle shape + lifecycle.
#
# Reuses the existing `aws_iam_role.lambda` execution role + CloudWatch
# log group naming so the operator surface stays uniform with the coach
# Lambda — single role, single dashboard, single alarm fan-out.

resource "aws_cloudwatch_log_group" "lambda_share_run" {
  name              = "/aws/lambda/${local.resource_prefix}-share-run"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.secrets.arn
  tags              = var.tags
}

resource "aws_lambda_function" "share_run" {
  function_name = "${local.resource_prefix}-share-run"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  # Node 24 — same runtime as the coach Lambda; @supabase/realtime-js
  # needs WS support that landed in Node 22+. Bumping here also
  # requires the esbuild target in apps/web/lambda/share-run/build.mjs
  # to match.
  runtime       = "nodejs24.x"
  architectures = ["arm64"]
  # 512 MB — the @resvg PNG renderer needs more headroom than the
  # coach handler's pure-streaming shape, but the static HTML path
  # is the hot one and runs well under 256 MB. 512 splits the
  # difference cheaply; an alarm on duration would tell us if PNG
  # cold-starts squeeze.
  memory_size                    = 512
  timeout                        = 15
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  filename         = local.effective_share_run_zip_path
  source_code_hash = filebase64sha256(local.effective_share_run_zip_path)

  publish = true

  environment {
    variables = local.share_run_lambda_env
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags

  # Same rationale as the coach Lambda — CI updates code on every
  # web@* tag; Terraform owns infra-shape (env, role, etc.).
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
    ]
  }

  depends_on = [aws_cloudwatch_log_group.lambda_share_run]
}

resource "aws_lambda_alias" "share_run_live" {
  name             = "live"
  function_name    = aws_lambda_function.share_run.function_name
  function_version = aws_lambda_function.share_run.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_lambda_function_url" "share_run" {
  function_name      = aws_lambda_function.share_run.function_name
  qualifier          = aws_lambda_alias.share_run_live.name
  authorization_type = "AWS_IAM"
  # Buffered (not streaming) — share-run returns a single HTML or PNG
  # body, no SSE. RESPONSE_STREAM would add latency overhead with no
  # benefit.
  invoke_mode = "BUFFERED"

  cors {
    # Crawlers + first-party viewers are the only callers; restrict
    # to GET / OPTIONS. No custom headers needed (no JWT — every read
    # is via the anon key inside the Lambda).
    allow_origins = ["https://${var.domain_name}"]
    allow_methods = ["GET"]
    allow_headers = ["content-type"]
    max_age       = 3600
  }
}

resource "aws_cloudfront_origin_access_control" "lambda_share_run" {
  name                              = "${local.resource_prefix}-share-run-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_lambda_permission" "cloudfront_invoke_share_run" {
  statement_id           = "AllowCloudFrontInvokeShareRun"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.share_run.function_name
  qualifier              = aws_lambda_alias.share_run_live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this.arn
  function_url_auth_type = "AWS_IAM"

  lifecycle {
    create_before_destroy = true
  }
}

# Second half of the two-grant OAC requirement — see
# aws_lambda_permission.cloudfront_invoke_function (issue #590).
resource "aws_lambda_permission" "cloudfront_invoke_function_share_run" {
  statement_id  = "AllowCloudFrontInvokeFunctionShareRun"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.share_run.function_name
  qualifier     = aws_lambda_alias.share_run_live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this.arn

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Share-route Lambda (Web SEO parity with share-run) ───
#
# Per-request SSR handler for /share/route/<id> (HTML + JSON-LD) +
# /og/route/<id>.png (privacy-clipped track PNG). Pre-fix, both routes
# were prerendered at build time via adapter-static (entries() from
# public_routes, capped at 5k); a route made public post-build (or
# beyond the cap) served the SPA-shell fallback `<head>` and a 404
# og:image until the next deploy, and a public→private flip stayed on
# S3 until overwritten. This Lambda fetches the route + clipped track
# at request time so every URL gets the right OG head AND a rendered
# image, regardless of build cadence. The PNG path falls back to a
# generic branded card (HTTP 200) for private / deleted routes so an
# unfurl never breaks. Symmetric mirror of the share-run Lambda above.
# See apps/web/lambda/share-route/README.md for the bundle shape +
# lifecycle.
#
# Reuses the existing `aws_iam_role.lambda` execution role + CloudWatch
# log group naming so the operator surface stays uniform across the
# three Lambdas — single role, single dashboard, single alarm fan-out.

resource "aws_cloudwatch_log_group" "lambda_share_route" {
  name              = "/aws/lambda/${local.resource_prefix}-share-route"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.secrets.arn
  tags              = var.tags
}

resource "aws_lambda_function" "share_route" {
  function_name = "${local.resource_prefix}-share-route"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  # Node 24 — same runtime as the coach + share-run Lambdas;
  # @supabase/realtime-js needs WS support that landed in Node 22+.
  # Bumping here also requires the esbuild target in
  # apps/web/lambda/share-route/build.mjs to match.
  runtime       = "nodejs24.x"
  architectures = ["arm64"]
  # 512 MB — the @resvg PNG renderer needs more headroom than a pure
  # HTML handler, but the static HTML path is the hot one and runs well
  # under 256 MB. 512 splits the difference cheaply; an alarm on
  # duration would tell us if PNG cold-starts squeeze. Matches the
  # share-run Lambda.
  memory_size                    = 512
  timeout                        = 15
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  filename         = local.effective_share_route_zip_path
  source_code_hash = filebase64sha256(local.effective_share_route_zip_path)

  publish = true

  environment {
    variables = local.share_route_lambda_env
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags

  # Same rationale as the coach + share-run Lambdas — CI updates code
  # on every web@* tag; Terraform owns infra-shape (env, role, etc.).
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
    ]
  }

  depends_on = [aws_cloudwatch_log_group.lambda_share_route]
}

resource "aws_lambda_alias" "share_route_live" {
  name             = "live"
  function_name    = aws_lambda_function.share_route.function_name
  function_version = aws_lambda_function.share_route.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_lambda_function_url" "share_route" {
  function_name      = aws_lambda_function.share_route.function_name
  qualifier          = aws_lambda_alias.share_route_live.name
  authorization_type = "AWS_IAM"
  # Buffered (not streaming) — share-route returns a single HTML or PNG
  # body, no SSE. RESPONSE_STREAM would add latency overhead with no
  # benefit.
  invoke_mode = "BUFFERED"

  cors {
    # Crawlers + first-party viewers are the only callers; restrict to
    # GET / OPTIONS. No custom headers needed (no JWT — every read is
    # via the anon key inside the Lambda).
    allow_origins = ["https://${var.domain_name}"]
    allow_methods = ["GET"]
    allow_headers = ["content-type"]
    max_age       = 3600
  }
}

resource "aws_cloudfront_origin_access_control" "lambda_share_route" {
  name                              = "${local.resource_prefix}-share-route-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_lambda_permission" "cloudfront_invoke_share_route" {
  statement_id           = "AllowCloudFrontInvokeShareRoute"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.share_route.function_name
  qualifier              = aws_lambda_alias.share_route_live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this.arn
  function_url_auth_type = "AWS_IAM"

  lifecycle {
    create_before_destroy = true
  }
}

# Second half of the two-grant OAC requirement — see
# aws_lambda_permission.cloudfront_invoke_function (issue #590).
resource "aws_lambda_permission" "cloudfront_invoke_function_share_route" {
  statement_id  = "AllowCloudFrontInvokeFunctionShareRoute"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.share_route.function_name
  qualifier     = aws_lambda_alias.share_route_live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this.arn

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Share-recap Lambda (Year-in-Running "Wrapped" share parity) ───
#
# Per-request SSR handler for /recap/share/<id> (HTML + OG tags) +
# /og/recap/<id>.png (1200x630 card PNG). Renders the FROZEN
# public_recaps snapshot — aggregate-only, no track, no per-run rows —
# so a recap published after the last web build still unfurls with the
# right per-recap head AND a rendered image, regardless of build
# cadence. The PNG path falls back to a generic branded card (HTTP 200)
# for missing / revoked recaps so an unfurl never breaks. Symmetric
# mirror of the share-run / share-route Lambdas above. See
# apps/web/lambda/share-recap/README.md for the bundle shape + lifecycle.
#
# Reuses the existing `aws_iam_role.lambda` execution role + CloudWatch
# log group naming so the operator surface stays uniform across the
# share Lambdas — single role, single dashboard, single alarm fan-out.

resource "aws_cloudwatch_log_group" "lambda_share_recap" {
  name              = "/aws/lambda/${local.resource_prefix}-share-recap"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.secrets.arn
  tags              = var.tags
}

resource "aws_lambda_function" "share_recap" {
  function_name = "${local.resource_prefix}-share-recap"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  # Node 24 — same runtime as the coach + share-run + share-route
  # Lambdas. Bumping here also requires the esbuild target in
  # apps/web/lambda/share-recap/build.mjs to match.
  runtime       = "nodejs24.x"
  architectures = ["arm64"]
  # 512 MB — the @resvg PNG renderer needs more headroom than a pure
  # HTML handler, but the static HTML path is the hot one and runs well
  # under 256 MB. 512 splits the difference cheaply. Matches the
  # share-run / share-route Lambdas.
  memory_size                    = 512
  timeout                        = 15
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  filename         = local.effective_share_recap_zip_path
  source_code_hash = filebase64sha256(local.effective_share_recap_zip_path)

  publish = true

  environment {
    variables = local.share_recap_lambda_env
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags

  # Same rationale as the coach + share-run + share-route Lambdas — CI
  # updates code on every web@* tag; Terraform owns infra-shape.
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
    ]
  }

  depends_on = [aws_cloudwatch_log_group.lambda_share_recap]
}

resource "aws_lambda_alias" "share_recap_live" {
  name             = "live"
  function_name    = aws_lambda_function.share_recap.function_name
  function_version = aws_lambda_function.share_recap.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_lambda_function_url" "share_recap" {
  function_name      = aws_lambda_function.share_recap.function_name
  qualifier          = aws_lambda_alias.share_recap_live.name
  authorization_type = "AWS_IAM"
  # Buffered (not streaming) — share-recap returns a single HTML or PNG
  # body, no SSE. RESPONSE_STREAM would add latency overhead with no
  # benefit.
  invoke_mode = "BUFFERED"

  cors {
    # Crawlers + first-party viewers are the only callers; restrict to
    # GET / OPTIONS. No custom headers needed (no JWT — every read is
    # via the anon key inside the Lambda).
    allow_origins = ["https://${var.domain_name}"]
    allow_methods = ["GET"]
    allow_headers = ["content-type"]
    max_age       = 3600
  }
}

resource "aws_cloudfront_origin_access_control" "lambda_share_recap" {
  name                              = "${local.resource_prefix}-share-recap-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_lambda_permission" "cloudfront_invoke_share_recap" {
  statement_id           = "AllowCloudFrontInvokeShareRecap"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.share_recap.function_name
  qualifier              = aws_lambda_alias.share_recap_live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this.arn
  function_url_auth_type = "AWS_IAM"

  lifecycle {
    create_before_destroy = true
  }
}

# Second half of the two-grant OAC requirement — see
# aws_lambda_permission.cloudfront_invoke_function (issue #590).
resource "aws_lambda_permission" "cloudfront_invoke_function_share_recap" {
  statement_id  = "AllowCloudFrontInvokeFunctionShareRecap"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.share_recap.function_name
  qualifier     = aws_lambda_alias.share_recap_live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this.arn

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Share-badge Lambda (per-badge achievement share parity) ───
#
# Per-request SSR handler for /share/badge/<id> (HTML + OG tags) +
# /og/badge/<id>.png (1200x630 card PNG). Renders the public,
# milestone-safe badge columns — a numeric milestone + a date, no track,
# no location — so a badge earned after the last web build still unfurls
# with the right per-badge head AND a rendered image, regardless of
# build cadence. The PNG path falls back to a generic branded card
# (HTTP 200) for missing / private badges so an unfurl never breaks.
# Symmetric mirror of the share-run / share-route / share-recap Lambdas
# above. See apps/web/lambda/share-badge/README.md for the bundle shape
# + lifecycle.
#
# Reuses the existing `aws_iam_role.lambda` execution role + CloudWatch
# log group naming so the operator surface stays uniform across the
# share Lambdas — single role, single dashboard, single alarm fan-out.

resource "aws_cloudwatch_log_group" "lambda_share_badge" {
  name              = "/aws/lambda/${local.resource_prefix}-share-badge"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.secrets.arn
  tags              = var.tags
}

resource "aws_lambda_function" "share_badge" {
  function_name = "${local.resource_prefix}-share-badge"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  # Node 24 — same runtime as the coach + share-run + share-route +
  # share-recap Lambdas. Bumping here also requires the esbuild target in
  # apps/web/lambda/share-badge/build.mjs to match.
  runtime       = "nodejs24.x"
  architectures = ["arm64"]
  # 512 MB — the @resvg PNG renderer needs more headroom than a pure
  # HTML handler, but the static HTML path is the hot one and runs well
  # under 256 MB. 512 splits the difference cheaply. Matches the
  # share-run / share-route / share-recap Lambdas.
  memory_size                    = 512
  timeout                        = 15
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  filename         = local.effective_share_badge_zip_path
  source_code_hash = filebase64sha256(local.effective_share_badge_zip_path)

  publish = true

  environment {
    variables = local.share_badge_lambda_env
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags

  # Same rationale as the coach + share-run + share-route + share-recap
  # Lambdas — CI updates code on every web@* tag; Terraform owns
  # infra-shape.
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
    ]
  }

  depends_on = [aws_cloudwatch_log_group.lambda_share_badge]
}

resource "aws_lambda_alias" "share_badge_live" {
  name             = "live"
  function_name    = aws_lambda_function.share_badge.function_name
  function_version = aws_lambda_function.share_badge.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_lambda_function_url" "share_badge" {
  function_name      = aws_lambda_function.share_badge.function_name
  qualifier          = aws_lambda_alias.share_badge_live.name
  authorization_type = "AWS_IAM"
  # Buffered (not streaming) — share-badge returns a single HTML or PNG
  # body, no SSE. RESPONSE_STREAM would add latency overhead with no
  # benefit.
  invoke_mode = "BUFFERED"

  cors {
    # Crawlers + first-party viewers are the only callers; restrict to
    # GET / OPTIONS. No custom headers needed (no JWT — every read is
    # via the anon key inside the Lambda).
    allow_origins = ["https://${var.domain_name}"]
    allow_methods = ["GET"]
    allow_headers = ["content-type"]
    max_age       = 3600
  }
}

resource "aws_cloudfront_origin_access_control" "lambda_share_badge" {
  name                              = "${local.resource_prefix}-share-badge-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_lambda_permission" "cloudfront_invoke_share_badge" {
  statement_id           = "AllowCloudFrontInvokeShareBadge"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.share_badge.function_name
  qualifier              = aws_lambda_alias.share_badge_live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this.arn
  function_url_auth_type = "AWS_IAM"

  lifecycle {
    create_before_destroy = true
  }
}

# Second half of the two-grant OAC requirement — see
# aws_lambda_permission.cloudfront_invoke_function (issue #590).
resource "aws_lambda_permission" "cloudfront_invoke_function_share_badge" {
  statement_id  = "AllowCloudFrontInvokeFunctionShareBadge"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.share_badge.function_name
  qualifier     = aws_lambda_alias.share_badge_live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this.arn

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Shared entity-SSR Lambda (/share/{event,profile,club,race,session,workout}) ───
#
# One HTML-only Lambda serving the six public entity share paths (see
# apps/web/lambda/share-entity/README.md). Same execution role + log
# group naming + CI-owns-code / Terraform-owns-shape lifecycle as the
# other share Lambdas. No @resvg / PNG path, so it runs comfortably at
# 256 MB (vs 512 for the image-rendering share Lambdas).

resource "aws_cloudwatch_log_group" "lambda_share_entity" {
  name              = "/aws/lambda/${local.resource_prefix}-share-entity"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.secrets.arn
  tags              = var.tags
}

resource "aws_lambda_function" "share_entity" {
  function_name = "${local.resource_prefix}-share-entity"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  # Node 24 — same runtime as the other share Lambdas. Bumping here also
  # requires the esbuild target in apps/web/lambda/share-entity/build.mjs.
  runtime       = "nodejs24.x"
  architectures = ["arm64"]
  # 256 MB — pure HTML handler (no PNG rasteriser), so it needs less
  # headroom than the 512 MB image-rendering share Lambdas.
  memory_size                    = 256
  timeout                        = 15
  reserved_concurrent_executions = var.lambda_reserved_concurrency

  filename         = local.effective_share_entity_zip_path
  source_code_hash = filebase64sha256(local.effective_share_entity_zip_path)

  publish = true

  environment {
    variables = local.share_entity_lambda_env
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags

  # CI updates code on every web@* tag; Terraform owns infra-shape.
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
    ]
  }

  depends_on = [aws_cloudwatch_log_group.lambda_share_entity]
}

resource "aws_lambda_alias" "share_entity_live" {
  name             = "live"
  function_name    = aws_lambda_function.share_entity.function_name
  function_version = aws_lambda_function.share_entity.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_lambda_function_url" "share_entity" {
  function_name      = aws_lambda_function.share_entity.function_name
  qualifier          = aws_lambda_alias.share_entity_live.name
  authorization_type = "AWS_IAM"
  # Buffered — a single HTML body, no SSE.
  invoke_mode = "BUFFERED"

  cors {
    allow_origins = ["https://${var.domain_name}"]
    allow_methods = ["GET"]
    allow_headers = ["content-type"]
    max_age       = 3600
  }
}

resource "aws_cloudfront_origin_access_control" "lambda_share_entity" {
  name                              = "${local.resource_prefix}-share-entity-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_lambda_permission" "cloudfront_invoke_share_entity" {
  statement_id           = "AllowCloudFrontInvokeShareEntity"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.share_entity.function_name
  qualifier              = aws_lambda_alias.share_entity_live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this.arn
  function_url_auth_type = "AWS_IAM"

  lifecycle {
    create_before_destroy = true
  }
}

# Second half of the two-grant OAC requirement — see
# aws_lambda_permission.cloudfront_invoke_function (issue #590).
resource "aws_lambda_permission" "cloudfront_invoke_function_share_entity" {
  statement_id  = "AllowCloudFrontInvokeFunctionShareEntity"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.share_entity.function_name
  qualifier     = aws_lambda_alias.share_entity_live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this.arn

  lifecycle {
    create_before_destroy = true
  }
}

# ─── Generate-route Lambda (server-side round-trip route generation) ───
#
# Non-streaming JSON handler for POST /api/routes/generate. Replaces the
# in-browser radial heuristic (which overshot target distances) with a
# self-hosted GraphHopper round_trip call: the handler fans out seeds to
# the engine and returns a finished loop polyline {coordinates, distanceM}.
# GRAPHHOPPER_URL is a server-only, non-secret engine URL passed as a
# Terraform var (NOT via sops); the browser never calls GraphHopper
# directly. When the URL is unset the endpoint returns 501 and the client
# falls back to the OSRM heuristic. See apps/web/lambda/generate-route/
# for the bundle shape + lifecycle.
#
# Reuses the existing `aws_iam_role.lambda` execution role + CloudWatch
# log group naming so the operator surface stays uniform across the
# Lambdas — single role, single dashboard, single alarm fan-out.

resource "aws_cloudwatch_log_group" "lambda_generate_route" {
  name              = "/aws/lambda/${local.resource_prefix}-generate-route"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.secrets.arn
  tags              = var.tags
}

resource "aws_lambda_function" "generate_route" {
  function_name = "${local.resource_prefix}-generate-route"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  # Node 24 — same runtime as the other Lambdas; the esbuild target in
  # apps/web/lambda/generate-route/build.mjs is pinned to node24 to match.
  runtime       = "nodejs24.x"
  architectures = ["arm64"]
  # 256 MB — the handler does a few fetch() round_trip calls and returns
  # one small GeoJSON line; no PNG renderer, no streaming. The hot path
  # is network-bound on the GraphHopper engine, not CPU.
  memory_size                    = 256
  timeout                        = 15
  reserved_concurrent_executions = var.generate_route_reserved_concurrency

  filename         = local.effective_generate_route_zip_path
  source_code_hash = filebase64sha256(local.effective_generate_route_zip_path)

  publish = true

  environment {
    variables = local.generate_route_lambda_env
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags

  # Same rationale as the other Lambdas — CI updates code on every web@*
  # tag; Terraform owns infra-shape (env, role, etc.).
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
    ]
  }

  depends_on = [aws_cloudwatch_log_group.lambda_generate_route]
}

resource "aws_lambda_alias" "generate_route_live" {
  name             = "live"
  function_name    = aws_lambda_function.generate_route.function_name
  function_version = aws_lambda_function.generate_route.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_lambda_function_url" "generate_route" {
  function_name      = aws_lambda_function.generate_route.function_name
  qualifier          = aws_lambda_alias.generate_route_live.name
  authorization_type = "AWS_IAM"
  # Buffered (not streaming) — generate-route returns a single small JSON
  # body, no SSE. RESPONSE_STREAM would add latency overhead with no benefit.
  invoke_mode = "BUFFERED"

  cors {
    allow_origins = ["https://${var.domain_name}"]
    allow_methods = ["POST"]
    # `x-amz-content-sha256` — the client-supplied sigv4 payload hash
    # OAC-signed POSTs require (issue #590 defect 3); the JWT rides
    # `x-supabase-authorization` (the OAC owns `Authorization`).
    allow_headers = ["content-type", "x-supabase-authorization", "x-amz-content-sha256"]
    max_age       = 3600
  }
}

resource "aws_cloudfront_origin_access_control" "lambda_generate_route" {
  name                              = "${local.resource_prefix}-generate-route-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_lambda_permission" "cloudfront_invoke_generate_route" {
  statement_id           = "AllowCloudFrontInvokeGenerateRoute"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.generate_route.function_name
  qualifier              = aws_lambda_alias.generate_route_live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this.arn
  function_url_auth_type = "AWS_IAM"

  lifecycle {
    create_before_destroy = true
  }
}

# Second half of the two-grant OAC requirement — see
# aws_lambda_permission.cloudfront_invoke_function (issue #590).
resource "aws_lambda_permission" "cloudfront_invoke_function_generate_route" {
  statement_id  = "AllowCloudFrontInvokeFunctionGenerateRoute"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.generate_route.function_name
  qualifier     = aws_lambda_alias.generate_route_live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this.arn

  lifecycle {
    create_before_destroy = true
  }
}

# ─── osrm-proxy Lambda (route-builder waypoint snapping/routing) ───
#
# GET-only JSON proxy for /api/routes/osrm/* — the route builder's manual
# waypoint snapping (`/nearest/v1/...`) and per-segment routing
# (`/route/v1/...`) against the self-hosted OSRM engine. Before this hop
# the browser fetched the OSRM host directly over a PUBLIC_ env, shipping
# the user's pin coordinates (routinely their home) with no server
# boundary (issue #198). OSRM_URL is a server-only, non-secret engine URL
# passed as a Terraform var, same treatment as GRAPHHOPPER_URL; the
# handler validates + rebuilds every upstream URL (no open relay) and
# requires a signed-in Supabase user. When the URL is unset the endpoint
# returns 501 and the builder degrades to straight-line segments. See
# apps/web/lambda/osrm-proxy/ for the bundle shape + lifecycle.

resource "aws_cloudwatch_log_group" "lambda_osrm_proxy" {
  name              = "/aws/lambda/${local.resource_prefix}-osrm-proxy"
  retention_in_days = 30
  kms_key_id        = aws_kms_key.secrets.arn
  tags              = var.tags
}

resource "aws_lambda_function" "osrm_proxy" {
  function_name = "${local.resource_prefix}-osrm-proxy"
  role          = aws_iam_role.lambda.arn
  handler       = "index.handler"
  # Node 24 — same runtime as the other Lambdas; the esbuild target in
  # apps/web/lambda/osrm-proxy/build.mjs is pinned to node24 to match.
  runtime       = "nodejs24.x"
  architectures = ["arm64"]
  # 256 MB — one auth round trip + one fetch() to OSRM per invocation;
  # network-bound, no rendering.
  memory_size                    = 256
  timeout                        = 15
  reserved_concurrent_executions = var.osrm_proxy_reserved_concurrency

  filename         = local.effective_osrm_proxy_zip_path
  source_code_hash = filebase64sha256(local.effective_osrm_proxy_zip_path)

  publish = true

  environment {
    variables = local.osrm_proxy_lambda_env
  }

  tracing_config {
    mode = "Active"
  }

  tags = var.tags

  # Same rationale as the other Lambdas — CI updates code on every web@*
  # tag; Terraform owns infra-shape (env, role, etc.).
  lifecycle {
    ignore_changes = [
      filename,
      source_code_hash,
    ]
  }

  depends_on = [aws_cloudwatch_log_group.lambda_osrm_proxy]
}

resource "aws_lambda_alias" "osrm_proxy_live" {
  name             = "live"
  function_name    = aws_lambda_function.osrm_proxy.function_name
  function_version = aws_lambda_function.osrm_proxy.version

  lifecycle {
    ignore_changes = [function_version]
  }
}

resource "aws_lambda_function_url" "osrm_proxy" {
  function_name      = aws_lambda_function.osrm_proxy.function_name
  qualifier          = aws_lambda_alias.osrm_proxy_live.name
  authorization_type = "AWS_IAM"
  # Buffered — each response is one small OSRM JSON document, no SSE.
  invoke_mode = "BUFFERED"

  cors {
    allow_origins = ["https://${var.domain_name}"]
    allow_methods = ["GET"]
    allow_headers = ["content-type"]
    max_age       = 3600
  }
}

resource "aws_cloudfront_origin_access_control" "lambda_osrm_proxy" {
  name                              = "${local.resource_prefix}-osrm-proxy-oac"
  origin_access_control_origin_type = "lambda"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_lambda_permission" "cloudfront_invoke_osrm_proxy" {
  statement_id           = "AllowCloudFrontInvokeOsrmProxy"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.osrm_proxy.function_name
  qualifier              = aws_lambda_alias.osrm_proxy_live.name
  principal              = "cloudfront.amazonaws.com"
  source_arn             = aws_cloudfront_distribution.this.arn
  function_url_auth_type = "AWS_IAM"

  lifecycle {
    create_before_destroy = true
  }
}

# Second half of the two-grant OAC requirement — see
# aws_lambda_permission.cloudfront_invoke_function (issue #590).
resource "aws_lambda_permission" "cloudfront_invoke_function_osrm_proxy" {
  statement_id  = "AllowCloudFrontInvokeFunctionOsrmProxy"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.osrm_proxy.function_name
  qualifier     = aws_lambda_alias.osrm_proxy_live.name
  principal     = "cloudfront.amazonaws.com"
  source_arn    = aws_cloudfront_distribution.this.arn

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
    # development-stage policy.
    #
    # `script-src 'unsafe-inline'` is kept HERE on purpose, but it is no
    # longer the binding policy. The static build inlines a per-page
    # hydration script, so this header must permit inline scripts at all —
    # but SvelteKit's `kit.csp` (hash mode) now emits a SECOND CSP as a
    # per-page `<meta http-equiv>` tag whose `script-src` is `'self'` plus
    # the SHA-256 hash of that page's inline script and NOTHING else (no
    # `'unsafe-inline'`). Browsers enforce header + meta as separate
    # policies and a script must satisfy BOTH, so the meta is the binding
    # `script-src` layer: an injected inline script has a hash absent from
    # the meta and is blocked. This is the defence-in-depth behind DOMPurify
    # that decisions §70 / audit-xss M2 wanted. Nonces are impossible for a
    # fully prerendered site (a static file is byte-identical to every
    # visitor, so a baked-in nonce is a constant), which is why hashes — not
    # the once-deferred CloudFront-Function nonce injection — are the fix.
    # /audit/owasp May 2026 High #1.
    content_security_policy {
      content_security_policy = join("; ", [
        "default-src 'self'",
        # OAuth avatar origins (lh3.googleusercontent.com from Google
        # sign-in, Apple's id.apple.com variants) plus Supabase
        # Storage signed URLs (run-photos bucket bytes) plus MapTiler
        # tile previews. `data:` is the family-level allowance — the
        # browser does NOT enforce MIME qualifiers on data: sources
        # in CSP (the `data:image/svg+xml` qualifier the previous
        # comment claimed was misleading). Real defence against a
        # `data:text/html` XSS regression is the avatar_url CHECK
        # constraint (`~* '^https?://'`, migration 20260808_001),
        # not this CSP line. /audit/owasp May 2026 Medium #4.
        "img-src 'self' data: https://*.supabase.co https://*.maptiler.com https://lh3.googleusercontent.com https://*.appleid.apple.com",
        "script-src 'self' 'unsafe-inline'",
        "style-src 'self' 'unsafe-inline'",
        "font-src 'self' data:",
        # `connect-src` covers fetch / XHR / EventSource / WebSocket —
        # everything the browser sends OUT. `*.ingest.sentry.io` is
        # where @sentry/sveltekit's browser SDK posts errors; without
        # it errors are silently CSP-blocked. `*.supabase.co` covers
        # REST + Realtime + Storage; `*.maptiler.com` covers tile
        # fetches. `wss://*.threkir.com` covers the Go live-hub WS
        # upgrade — the spectator page would otherwise be CSP-blocked
        # the moment PUBLIC_LIVE_HUB_URL lands in prod. /audit/owasp
        # May 2026 High #2a.
        "connect-src 'self' https://*.supabase.co https://api.threkir.com https://*.maptiler.com https://*.ingest.sentry.io wss://*.threkir.com",
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
  # With caching disabled (all TTLs 0) CloudFront rejects any non-none
  # cache-key contribution ("CookieBehavior is invalid for policy with
  # caching disabled"). Forwarding cookies / query strings / headers to
  # the origin is the origin request policy's job (`lambda` above),
  # which already carries all of them.
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
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
  # `Accept-Encoding` is excluded here and in every policy below: the
  # CreateOriginRequestPolicy API rejects it outright (InvalidArgument)
  # — CloudFront owns that header; the cacheable behaviors forward a
  # normalized form via the cache policies' enable_accept_encoding_*.
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = [
        "content-type",
        "accept",
        "x-supabase-authorization",
      ]
    }
  }
}

# Cache policy for the share-run Lambda. UNLIKE the coach passthrough
# (no caching — coach streams personalised content), share-run
# responses are deterministic per URL (same run id → same HTML / PNG)
# and the freshness window is hours-long. Cache for 1 hour at the
# edge so a crawler storm against a single share URL costs at most
# one Lambda invocation per cache window.
resource "aws_cloudfront_cache_policy" "share_run" {
  name = "${local.resource_prefix}-share-run"
  # 5-min TTL — persona-hunt Round 3 finding Privacy #3. The
  # previous 1h pinned a public→private visibility flip to a
  # 1h propagation window on the OG unfurl. The Lambda's
  # Cache-Control header is now `max-age=300, s-maxage=300,
  # stale-while-revalidate=60`; both must match because either
  # ceiling (CloudFront's max_ttl OR the origin's Cache-Control)
  # ends up clamping the stale window.
  comment     = "Share-run Lambda — cache per-id HTML for 5m so visibility flips propagate fast"
  default_ttl = 300
  max_ttl     = 300
  min_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    # Path varies per run id; CloudFront already keys on the path
    # without any query-string contribution. Disable QS-in-key so a
    # `?foo=bar` doesn't multiply cache entries.
    query_strings_config { query_string_behavior = "none" }
  }
}

# Origin request policy for the share-run Lambda. The Lambda doesn't
# need any viewer headers (it builds the response purely from the
# URL path + its own env vars), so forward nothing extra — keeps the
# cache key tight and the OAC signature unambiguous.
resource "aws_cloudfront_origin_request_policy" "share_run" {
  name = "${local.resource_prefix}-share-run-origin"
  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "none" }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["accept"]
    }
  }
}

# Cache + origin-request policies for the share-route Lambda. Same
# shape + 5-min TTL as the share-run policies (responses are
# deterministic per URL and visibility flips must propagate fast). Kept
# as dedicated resources rather than sharing the share-run ones so a
# future tweak to one share surface can't silently change the other.
resource "aws_cloudfront_cache_policy" "share_route" {
  name = "${local.resource_prefix}-share-route"
  # 5-min TTL — matches the Lambda's `max-age=300, s-maxage=300,
  # stale-while-revalidate=60` Cache-Control. Both ceilings (CloudFront
  # max_ttl AND the origin Cache-Control) clamp the stale window, so
  # they must agree. Caps how long a public→private route flip stays on
  # the OG unfurl.
  comment     = "Share-route Lambda — cache per-id HTML/PNG for 5m so visibility flips propagate fast"
  default_ttl = 300
  max_ttl     = 300
  min_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    # Path varies per route id; CloudFront already keys on the path
    # without any query-string contribution. Disable QS-in-key so a
    # `?foo=bar` doesn't multiply cache entries.
    query_strings_config { query_string_behavior = "none" }
  }
}

resource "aws_cloudfront_origin_request_policy" "share_route" {
  name = "${local.resource_prefix}-share-route-origin"
  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "none" }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["accept"]
    }
  }
}

# Cache + origin-request policies for the share-recap Lambda. Same
# shape + 5-min TTL as the share-run / share-route policies (responses
# are deterministic per URL and a recap revocation must propagate
# fast). Kept as dedicated resources rather than sharing the sibling
# ones so a future tweak to one share surface can't silently change
# the others.
resource "aws_cloudfront_cache_policy" "share_recap" {
  name = "${local.resource_prefix}-share-recap"
  # 5-min TTL — matches the Lambda's `max-age=300, s-maxage=300,
  # stale-while-revalidate=60` Cache-Control. Both ceilings (CloudFront
  # max_ttl AND the origin Cache-Control) clamp the stale window, so
  # they must agree. Caps how long a revoked recap stays on the unfurl.
  comment     = "Share-recap Lambda — cache per-id HTML/PNG for 5m so recap revocations propagate fast"
  default_ttl = 300
  max_ttl     = 300
  min_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    # Path varies per recap id; CloudFront already keys on the path
    # without any query-string contribution. Disable QS-in-key so a
    # `?foo=bar` doesn't multiply cache entries.
    query_strings_config { query_string_behavior = "none" }
  }
}

resource "aws_cloudfront_origin_request_policy" "share_recap" {
  name = "${local.resource_prefix}-share-recap-origin"
  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "none" }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["accept"]
    }
  }
}

# Cache + origin-request policies for the share-badge Lambda. Same
# shape + 5-min TTL as the share-run / share-route / share-recap
# policies (responses are deterministic per URL and a badge made private
# must propagate fast). Kept as dedicated resources rather than sharing
# the sibling ones so a future tweak to one share surface can't silently
# change the others.
resource "aws_cloudfront_cache_policy" "share_badge" {
  name = "${local.resource_prefix}-share-badge"
  # 5-min TTL — matches the Lambda's `max-age=300, s-maxage=300,
  # stale-while-revalidate=60` Cache-Control. Both ceilings (CloudFront
  # max_ttl AND the origin Cache-Control) clamp the stale window, so
  # they must agree. Caps how long a privated badge stays on the unfurl.
  comment     = "Share-badge Lambda — cache per-id HTML/PNG for 5m so badge privacy changes propagate fast"
  default_ttl = 300
  max_ttl     = 300
  min_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    # Path varies per badge id; CloudFront already keys on the path
    # without any query-string contribution. Disable QS-in-key so a
    # `?foo=bar` doesn't multiply cache entries.
    query_strings_config { query_string_behavior = "none" }
  }
}

resource "aws_cloudfront_origin_request_policy" "share_badge" {
  name = "${local.resource_prefix}-share-badge-origin"
  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "none" }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["accept"]
    }
  }
}

# Cache + origin-request policies for the shared entity-SSR Lambda. Same
# 5-min TTL + Cache-Control agreement as the other share Lambdas so a
# privated/deleted entity drops off the unfurl within 5 minutes.
resource "aws_cloudfront_cache_policy" "share_entity" {
  name        = "${local.resource_prefix}-share-entity"
  comment     = "Share-entity Lambda — cache per-entity HTML for 5m so privacy/deletion changes propagate fast"
  default_ttl = 300
  max_ttl     = 300
  min_ttl     = 0
  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = true
    enable_accept_encoding_gzip   = true
    cookies_config { cookie_behavior = "none" }
    headers_config { header_behavior = "none" }
    query_strings_config { query_string_behavior = "none" }
  }
}

resource "aws_cloudfront_origin_request_policy" "share_entity" {
  name = "${local.resource_prefix}-share-entity-origin"
  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "none" }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["accept"]
    }
  }
}

# Origin request policy for the generate-route Lambda. Server-side route
# generation is a Pro perk (decisions §204), so the viewer JWT rides
# `x-supabase-authorization` to the handler's is_pro() gate — same slot as
# the coach policy. `Authorization` is still excluded: the Lambda OAC takes
# that header for its sigv4 signature, and forwarding the viewer's would
# 403 the origin.
resource "aws_cloudfront_origin_request_policy" "generate_route" {
  name = "${local.resource_prefix}-generate-route-origin"
  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "none" }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["content-type", "accept", "x-supabase-authorization"]
    }
  }
}

# Origin request policy for the osrm-proxy Lambda. Same viewer-JWT slot as
# generate-route (`x-supabase-authorization` — the OAC owns `Authorization`),
# but the OSRM calls are GETs whose meaning rides the query string
# (radiuses / overview / geometries), so query strings are forwarded. The
# handler allowlists + rebuilds them; nothing else is passed through.
resource "aws_cloudfront_origin_request_policy" "osrm_proxy" {
  name = "${local.resource_prefix}-osrm-proxy-origin"
  cookies_config { cookie_behavior = "none" }
  query_strings_config { query_string_behavior = "all" }
  headers_config {
    header_behavior = "whitelist"
    headers {
      items = ["accept", "x-supabase-authorization"]
    }
  }
}

# Viewer-request function: 301 www.* -> apex (SEO duplicate-content
# consolidation). Gated on redirect_www_to_apex so only envs that
# serve a www alias (prod) create + associate it; preview has no www
# host, so the count is 0 and no behavior references it.
resource "aws_cloudfront_function" "www_redirect" {
  count   = var.redirect_www_to_apex ? 1 : 0
  name    = "${local.resource_prefix}-www-redirect"
  runtime = "cloudfront-js-2.0"
  comment = "301 redirect www.* to the bare apex host"
  publish = true
  code    = file("${path.module}/functions/www_redirect.js")
}

# Association list is empty (no www redirect) or a single-element list
# (associate the function). Consumed by a `dynamic "function_association"`
# in every cache behavior so the redirect applies to ALL paths, not just
# the default (a www link to /share/run/* must consolidate too).
locals {
  www_redirect_associations = var.redirect_www_to_apex ? [aws_cloudfront_function.www_redirect[0].arn] : []
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

  origin {
    origin_id                = "lambda-share-run"
    domain_name              = replace(aws_lambda_function_url.share_run.function_url, "/^https?:\\/\\/([^/]+)\\/?.*$/", "$1")
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda_share_run.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    origin_id                = "lambda-share-route"
    domain_name              = replace(aws_lambda_function_url.share_route.function_url, "/^https?:\\/\\/([^/]+)\\/?.*$/", "$1")
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda_share_route.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    origin_id                = "lambda-share-recap"
    domain_name              = replace(aws_lambda_function_url.share_recap.function_url, "/^https?:\\/\\/([^/]+)\\/?.*$/", "$1")
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda_share_recap.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    origin_id                = "lambda-share-badge"
    domain_name              = replace(aws_lambda_function_url.share_badge.function_url, "/^https?:\\/\\/([^/]+)\\/?.*$/", "$1")
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda_share_badge.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    origin_id                = "lambda-share-entity"
    domain_name              = replace(aws_lambda_function_url.share_entity.function_url, "/^https?:\\/\\/([^/]+)\\/?.*$/", "$1")
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda_share_entity.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    origin_id                = "lambda-generate-route"
    domain_name              = replace(aws_lambda_function_url.generate_route.function_url, "/^https?:\\/\\/([^/]+)\\/?.*$/", "$1")
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda_generate_route.id

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  origin {
    origin_id                = "lambda-osrm-proxy"
    domain_name              = replace(aws_lambda_function_url.osrm_proxy.function_url, "/^https?:\\/\\/([^/]+)\\/?.*$/", "$1")
    origin_access_control_id = aws_cloudfront_origin_access_control.lambda_osrm_proxy.id

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

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
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

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # Generate-route Lambda: server-side round-trip route generation for
  # POST /api/routes/generate. Reuses the coach passthrough cache policy
  # (no caching — a generate POST is unique per request and must never be
  # served from cache), with a dedicated origin-request policy that
  # forwards no viewer JWT. compress is off: the JSON body is tiny.
  ordered_cache_behavior {
    path_pattern               = "/api/routes/generate*"
    target_origin_id           = "lambda-generate-route"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = false
    cache_policy_id            = aws_cloudfront_cache_policy.lambda_passthrough.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.generate_route.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # osrm-proxy Lambda: route-builder waypoint snapping/routing for
  # GET /api/routes/osrm/*. No caching (routing responses are per-user,
  # per-coordinate); the dedicated origin-request policy forwards the
  # query string the OSRM GETs carry.
  ordered_cache_behavior {
    path_pattern               = "/api/routes/osrm*"
    target_origin_id           = "lambda-osrm-proxy"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = false
    cache_policy_id            = aws_cloudfront_cache_policy.lambda_passthrough.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.osrm_proxy.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # Share-run Lambda: per-request SSR for share-link HTML so brand-
  # new runs unfurl with the right per-run head, regardless of build
  # cadence. Persona-hunt finding Casual #4. See
  # apps/web/lambda/share-run/README.md.
  ordered_cache_behavior {
    path_pattern               = "/share/run/*"
    target_origin_id           = "lambda-share-run"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.share_run.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_run.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # Per-run og:image PNG, same Lambda. Pre-fix this stayed adapter-
  # static-prerendered on S3 with a 50k cap, so a run created after
  # the last build (or beyond the cap) 404'd and its social unfurl
  # showed a broken image. Routing /og/run/* to the share-run Lambda
  # renders the card at request time for ANY id (with a generic
  # branded fallback for private / deleted runs). compress is off:
  # the body is already-compressed PNG bytes. Persona-hunt round-5
  # finding very-social.
  ordered_cache_behavior {
    path_pattern               = "/og/run/*"
    target_origin_id           = "lambda-share-run"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = false
    cache_policy_id            = aws_cloudfront_cache_policy.share_run.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_run.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # Share-route Lambda: per-request SSR for route share-link HTML +
  # JSON-LD so brand-new (or post-build-public) routes unfurl with the
  # right per-route head, regardless of build cadence. Web SEO parity
  # with share-run. See apps/web/lambda/share-route/README.md.
  ordered_cache_behavior {
    path_pattern               = "/share/route/*"
    target_origin_id           = "lambda-share-route"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.share_route.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_route.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # Per-route og:image PNG, same Lambda. Pre-fix this stayed adapter-
  # static-prerendered on S3 with a 5k cap, so a route made public
  # after the last build (or beyond the cap) 404'd and its social
  # unfurl showed a broken image. Routing /og/route/* to the
  # share-route Lambda renders the card at request time for ANY id
  # (with a generic branded fallback for private / deleted routes).
  # compress is off: the body is already-compressed PNG bytes.
  ordered_cache_behavior {
    path_pattern               = "/og/route/*"
    target_origin_id           = "lambda-share-route"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = false
    cache_policy_id            = aws_cloudfront_cache_policy.share_route.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_route.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # Share-recap Lambda: per-request SSR for the Year-in-Running
  # "Wrapped" share-link HTML so a recap published after the last build
  # unfurls with the right per-recap head, regardless of build cadence.
  # Renders the frozen public_recaps snapshot. See
  # apps/web/lambda/share-recap/README.md.
  ordered_cache_behavior {
    path_pattern               = "/recap/share/*"
    target_origin_id           = "lambda-share-recap"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.share_recap.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_recap.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # Per-recap og:image PNG, same Lambda. Routing /og/recap/* to the
  # share-recap Lambda renders the 1200x630 card at request time for ANY
  # id (with a generic branded fallback at 200 for missing / revoked
  # recaps). compress is off: the body is already-compressed PNG bytes.
  ordered_cache_behavior {
    path_pattern               = "/og/recap/*"
    target_origin_id           = "lambda-share-recap"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = false
    cache_policy_id            = aws_cloudfront_cache_policy.share_recap.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_recap.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # Share-badge Lambda: per-request SSR for the per-badge achievement
  # share-link HTML so a badge earned after the last build unfurls with
  # the right per-badge head, regardless of build cadence. Renders the
  # public, milestone-safe badge columns. See
  # apps/web/lambda/share-badge/README.md.
  ordered_cache_behavior {
    path_pattern               = "/share/badge/*"
    target_origin_id           = "lambda-share-badge"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.share_badge.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_badge.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # Per-badge og:image PNG, same Lambda. Routing /og/badge/* to the
  # share-badge Lambda renders the 1200x630 card at request time for ANY
  # id (with a generic branded fallback at 200 for missing / private
  # badges). compress is off: the body is already-compressed PNG bytes.
  ordered_cache_behavior {
    path_pattern               = "/og/badge/*"
    target_origin_id           = "lambda-share-badge"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = false
    cache_policy_id            = aws_cloudfront_cache_policy.share_badge.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_badge.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # Shared entity-SSR Lambda: per-request SSR HTML for the six public
  # entity share paths so a newly-created/edited entity unfurls with the
  # right per-entity head regardless of build cadence. HTML only (no
  # og:image PNG). See apps/web/lambda/share-entity/README.md.
  ordered_cache_behavior {
    path_pattern               = "/share/event/*"
    target_origin_id           = "lambda-share-entity"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.share_entity.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_entity.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  ordered_cache_behavior {
    path_pattern               = "/share/profile/*"
    target_origin_id           = "lambda-share-entity"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.share_entity.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_entity.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  ordered_cache_behavior {
    path_pattern               = "/share/club/*"
    target_origin_id           = "lambda-share-entity"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.share_entity.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_entity.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  ordered_cache_behavior {
    path_pattern               = "/share/race/*"
    target_origin_id           = "lambda-share-entity"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.share_entity.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_entity.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  ordered_cache_behavior {
    path_pattern               = "/share/session/*"
    target_origin_id           = "lambda-share-entity"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.share_entity.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_entity.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  ordered_cache_behavior {
    path_pattern               = "/share/workout/*"
    target_origin_id           = "lambda-share-entity"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = aws_cloudfront_cache_policy.share_entity.id
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.share_entity.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.security.id

    dynamic "function_association" {
      for_each = local.www_redirect_associations
      content {
        event_type   = "viewer-request"
        function_arn = function_association.value
      }
    }
  }

  # SPA fallback — adapter-static's fallback is build/200.html, and the
  # mapping below is what serves it. It was index.html until § 1268 moved
  # the shell so the prerendered landing page could take that name; this
  # line said `index.html` for a day after the move, contradicting the
  # paragraph 30 lines down that states the opposite outright.
  #
  # These apply to EVERY origin on the distribution, not just S3.
  # CloudFront models custom error responses per DISTRIBUTION; there is no
  # per-cache-behaviour form, so a 403 returned by any of the eight Lambda
  # origins above is rewritten to the shell at 200 as well — which is the
  # subject of an open followup, because it reaches an API caller as a
  # 200 text/html body where a refusal was sent. 404 is NOT mapped: § 1022
  # added one and § 1084 removed it again, so the sentence that used to sit
  # here describing "a 404 to the shell at 404" outlived its own mapping and
  # disagreed with the block immediately below. The comment
  # here used to claim the opposite — that a Lambda's own 404 surfaced as a real
  # 404 because its behaviour ran first — and the `cloudfront_invoke_function`
  # block above records the measurement that disproves it: with only one of the
  # two OAC grants the Function URL 403s before invocation, this fallback
  # rewrites that 403 into the shell at 200, and the surface reads healthy while
  # the Lambda never runs (issue #590, proven 2026-07-21). Two comments in one
  # file cannot both be true; this is the one that was wrong.
  #
  # The consequence is a monitoring contract, not a config one: a Lambda-origin
  # failure is invisible to a viewer AND to a synthetic check, so every Lambda
  # in this module carries an error-rate alarm and a p95 alarm in alarms.tf, and
  # the two engine-backed ones additionally carry an `engine_unreachable` log
  # filter for the clean-502 path the Errors metric never sees. That coverage is
  # the only signal these failures have; `scripts/check_infra_coverage.mjs`
  # fails the PR when a function is added without it.
  #
  # 403 is the one status mapped to the shell, and it is mapped because the
  # S3 bucket policy grants
  # s3:GetObject only (no s3:ListBucket), so S3 answers a missing key
  # with 403 AccessDenied, not 404 — a deep-link / hard-refresh / crawl
  # of a dynamic client route (/dashboard, /runs/<id>, /u/<id>, …) hits
  # the 403 path. Without the 403 mapping those routes surface
  # AccessDenied instead of the SPA. This is the standard CloudFront+S3
  # SPA idiom; the distribution serves no genuinely access-protected S3
  # keys (all objects are the public static build), so nothing legitimate
  # is masked by turning 403 into the shell.
  #
  # The shell is /200.html and NOT /index.html: since decisions § 1268 the
  # landing page is prerendered onto index.html, and that document is not a
  # shell — its asset URLs are relative (`./_app/…`, resolved against the
  # request path, so nothing loads under /runs/<id>) and its hydration payload
  # names route "/". Pointing this back at /index.html serves the landing page,
  # broken, for every client route. `apps/web/src/lib/seo/spa_shell_filename.test.ts`
  # reads this block, apps/web/svelte.config.js's adapter fallback and the five
  # share Lambdas' build scripts, and fails when they disagree.
  #
  # Changing this value has a deploy order: /200.html must exist in the bucket
  # BEFORE the apply, or every deep link resolves to a missing error page. See
  # docs/features/seo.md § Deploying a change to the shell filename, and
  # docs/ops/deployment.md § One-off: the SPA-shell cutover for the operator
  # sequence with its rollback.
  custom_error_response {
    error_code         = 403
    response_code      = 200
    response_page_path = "/200.html"
  }

  # There is deliberately NO `custom_error_response` for 404, and
  # `scripts/check_infra_error_responses.mjs` fails the PR if one comes back.
  #
  # § 1022 added one because the five share Lambdas' own 404 bodies were a
  # single unstyled English sentence, so the shell had to be substituted for
  # them; the cost was that the substitution also discarded the `noindex` those
  # bodies carried, which is the tag the whole crawler fix was about. § 1036
  # made all five return the SPA shell AT 404 themselves — through the same
  # `injectEntityHead` that strips a stale `og:*`/canonical/JSON-LD — so the
  # premise is gone and the mapping now only replaces an honest body with an
  # identical one, minus the tag. Dropping it is what puts the `noindex` on the
  # wire. It also stops `/api/coach*` answering a JSON 404 as an HTML shell.
  #
  # S3 never reaches this path anyway: the bucket policy grants s3:GetObject
  # with no s3:ListBucket, so a missing key is 403 AccessDenied and lands on
  # the block above. decisions § 1084.
  #
  # 403 stays at 200 and MUST: that is the deep-link path (every dynamic
  # client route is a missing S3 key), and answering it 403 would break the
  # whole SPA. decisions § 1022.

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
