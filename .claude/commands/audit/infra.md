---
description: Audit the AWS Terraform stacks under infra/ — IAM least-privilege, encryption, drift hygiene, cost + DR guardrails
---

Audit the Terraform stacks at `infra/` against the AWS-hosting plan ([decisions.md § 53](../../../docs/architecture/decisions.md#53-web-app--domain-on-aws-s3--cloudfront--lambda--route-53-not-vercel-or-cloudflare-pages)).

## Goal

The web app's blast radius runs through these stacks: a permissive OIDC trust policy makes the entire AWS account writable from a fork's PR; a public S3 bucket undoes the privacy story for the runs that the static build links to; a missing `lifecycle.ignore_changes` makes Terraform fight CI on every deploy. Catch the high-cost mistakes before `terraform apply` reaches a real account.

## What to check

1. **State bucket + S3-native locking.** `infra/bootstrap/main.tf` — bucket has Public Access Block (all four flags), `versioning_configuration { status = "Enabled" }`, server-side encryption (`AES256` at minimum, `aws:kms` better), and a non-trivial deletion path (no `force_destroy = true`). Every non-bootstrap stack has a `backend "s3"` block pointing at this bucket with `encrypt = true` and `use_lockfile = true` (S3-native locking, Terraform ≥ 1.10). **Flag any stack still using `dynamodb_table = ...`** — that's the legacy locking path and should be removed alongside the DynamoDB resource. The `terraform_remote_state` data sources also use `use_lockfile = true` (or omit lock config entirely — read-only data sources don't lock).

2. **OIDC trust policy.** `infra/github-oidc/main.tf` — both `aws_iam_role.deploy_*` resources have `Condition` blocks that pin BOTH `:aud = "sts.amazonaws.com"` AND a `:sub` `StringLike` matching exactly the intended ref (`refs/tags/web@*` for prod, `refs/heads/main` for preview). Wildcards or missing `:sub` conditions are the canonical "fork PR can assume your role" footgun. Thumbprints in `thumbprint_list` exist (AWS validates them inline now, but the field is required).

3. **OIDC role permissions.** Same file — each role's `aws_iam_role_policy` is scoped per-resource: S3 actions limited to the env's bucket ARN (no `*`), Lambda actions limited to `function:threkir-web-<env>-coach*`, CloudFront `CreateInvalidation` is the only CF action (not `cloudfront:*`). No `iam:*` / `sts:AssumeRole` / `secretsmanager:*` / `kms:*` actions on the deploy role.

4. **S3 buckets.** `bootstrap/main.tf` (state) and `modules/web-stack/main.tf` (site) — every bucket has:
   - `aws_s3_bucket_public_access_block` with all four flags `true`
   - `aws_s3_bucket_versioning` enabled
   - `aws_s3_bucket_server_side_encryption_configuration` set
   - A `aws_s3_bucket_policy` that grants `Principal: { Service = "cloudfront.amazonaws.com" }` ONLY (not `Principal: "*"`) and conditions on `AWS:SourceArn`
   - No legacy `aws_s3_bucket_acl` (the modern API forbids ACLs)
   - A lifecycle rule expiring non-current versions (cost guardrail; the site bucket has one, the state bucket doesn't need to)

5. **CloudFront distribution.** `modules/web-stack/main.tf` — every behavior:
   - `viewer_protocol_policy = "redirect-to-https"` (default behavior) or `"https-only"` (Lambda behavior)
   - `minimum_protocol_version = "TLSv1.2_2021"` or stricter
   - `origin_access_control_id` set on the S3 origin (not the legacy `origin_access_identity`)
   - `origin_protocol_policy = "https-only"` on the Lambda origin
   - `response_headers_policy_id` attached to BOTH default and ordered behaviors
   - The response-headers policy has `strict_transport_security` (max_age ≥ 1 year, `include_subdomains`, `preload`), `content_type_options`, `referrer_policy`, `frame_options = "DENY"`, and a `content_security_policy` (permissive at first is OK; `default-src 'self'` plus listed origins is the floor)
   - `price_class = "PriceClass_100"` or `PriceClass_200` (not `PriceClass_All` unless explicitly justified — meaningful cost difference)
   - SPA fallback `custom_error_response` rewrites 404 → 200 + `/index.html`

6. **Lambda function.** `modules/web-stack/main.tf` —
   - `runtime = "nodejs20.x"` or newer (no `nodejs18.x` — deprecated Sept 2025)
   - `architectures = ["arm64"]` (Graviton is cheaper for the same code)
   - `memory_size` + `timeout` reasonable (1024 MB / 30 s for streaming)
   - `aws_iam_role` for the Lambda has only `AWSLambdaBasicExecutionRole` attached unless extra perms are documented
   - `aws_lambda_function_url` has `authorization_type = "NONE"` only when fronted by CloudFront — confirm CORS `allow_origins` is restricted to the site domain, not `["*"]`
   - `aws_lambda_alias.live` exists, `aws_lambda_function_url.qualifier` points at the alias (not `$LATEST`)
   - `lifecycle.ignore_changes` lists `filename`, `source_code_hash`, `version`, `qualified_arn` so CI's `update-function-code` doesn't fight Terraform; same for the alias's `function_version`. **Verify the list is minimal** — anything else in `ignore_changes` is suspicious.
   - `aws_cloudwatch_log_group` for the Lambda has `retention_in_days` set (default infinite is a cost trap).

7. **KMS keys.** `modules/web-stack/main.tf` —
   - `enable_key_rotation = true`
   - `deletion_window_in_days >= 7` (default 30 is fine)
   - One key per env (not shared between prod and preview)
   - `aws_kms_alias` exists alongside the key (sops + future rotation are easier with aliases)

8. **Secrets handling.**
   - `infra/.sops.yaml` `creation_rules` cover `envs/prod/secrets.enc.yaml` and `envs/preview/secrets.enc.yaml`. ARNs may be placeholders (e.g. `REPLACE_PROD_KMS_ARN`) until first apply — document if so.
   - **`infra/envs/*/secrets.enc.yaml` files, if present, are actually encrypted.** Open and confirm the file contains `sops:` metadata at the bottom and ENC[ blocks, not plaintext.
   - **`infra/envs/*/terraform.tfvars` is gitignored.** `terraform.tfvars.example` is committed as a template; the real file is per-developer / per-env.
   - Variables holding secrets (`public_supabase_anon_key` is publishable so it's borderline; any real secret) marked `sensitive = true`.
   - No `output` exposes a sensitive value without `sensitive = true`.

9. **Provider + Terraform pinning.**
   - Every stack has a `versions.tf` with `required_version = ">= 1.13"` (or current) and pinned `required_providers`.
   - Provider versions use `~> X.Y` or exact pins.
   - `.terraform.lock.hcl` should be committed once `terraform init` has been run for each stack — flag if missing in stacks that have been initialized.

10. **Cross-region wiring.** `modules/web-stack` declares `configuration_aliases = [aws.us_east_1]`. The ACM cert (in `dns/main.tf`) uses `provider = aws.us_east_1`. Per-env stacks correctly pass `aws.us_east_1` in their `module "web" { providers = { ... } }` block. Wrong wiring here surfaces as cert validation hangs.

11. **Drift hygiene.** Read every `lifecycle { ignore_changes = [...] }` block — list each one and confirm:
    - It's there because CI legitimately mutates the field, AND
    - The list is minimal — adding `lifecycle.ignore_changes = [tags]` for example would silently let manual console changes accumulate.

12. **Cost guardrails.**
    - CloudWatch log retention set on every log group (default = forever).
    - S3 lifecycle expiring non-current versions on the site bucket (no rule = unbounded version growth).
    - CloudFront `price_class` set.
    - Lambda has no `reserved_concurrent_executions` set unbounded high (default unbounded is fine for low-volume; just verify it's not a runaway).

13. **Tagging.** Every resource that supports `tags` has them, and the tag set includes at minimum `project`, `env`, `managed = "terraform"`. The module passes `var.tags` through to every taggable resource. Cost attribution + ownership both depend on this.

14. **DR posture.** Match against [`apps/web/deployment.md` § Disaster recovery](../../../apps/web/deployment.md#disaster-recovery):
    - State bucket has versioning enabled (so a corrupt apply can be reverted from a previous state version).
    - KMS keys have a deletion window long enough that a misclick can be reversed.
    - Lambda alias separates the deployable code from the function shape (so rollback is `update-alias`, not a full Terraform redeploy).

15. **No shared global resources.** Per-env stacks must not name resources without an env suffix — e.g. a CloudFront response-headers policy named `threkir-web-security` (no env) would conflict between prod and preview. Confirm `local.resource_prefix = "threkir-web-${var.env}"` is used for every named resource.

## Report

- **Critical** — OIDC trust policy too broad (fork PR can assume role), public S3 bucket without OAC, secrets file committed in plaintext, KMS rotation disabled with long-lived keys.
- **High** — bucket versioning off, missing PAB on a bucket, CloudFront serving non-HTTPS, Lambda runtime deprecated, role permissions over-scoped (`*` instead of specific ARNs), `terraform.tfvars` not gitignored.
- **Medium** — log retention infinite, missing security headers, weak CSP, missing tags, drift-prone resource (no `ignore_changes` on a CI-mutated field).
- **Low** — version pin loose (no `~>`), undocumented `lifecycle` choice, missing `sensitive = true` on a borderline value, missing `aws_kms_alias` companion to a key.

For each finding: file:line + the concrete change to make. Don't apply fixes without explicit confirmation.

## Useful starting points

- `infra/README.md` — the apply-order walkthrough, lists every stack
- `infra/bootstrap/main.tf` — state bucket + DDB lock
- `infra/modules/web-stack/{main,alarms,variables,outputs}.tf` — the per-env stack
- `infra/dns/main.tf` — Route 53 + ACM cert (us-east-1 provider)
- `infra/github-oidc/main.tf` — OIDC + deploy roles (this file has the highest blast-radius surface)
- `infra/envs/{prod,preview}/main.tf` — root-module wiring
- `apps/web/deployment.md` — what the architecture is supposed to look like; finding deltas against that doc IS a finding
- `docs/architecture/decisions.md § 53` — the rationale + the architecture diagram pinned by this stack

## Delegate to

`general-purpose` agent with this file as the prompt body. The audit reads ~30 small `.tf` files plus checks 2–3 conditions per file, well within one agent's reading window.

Read-only. Findings only. Don't run `terraform plan` or `terraform apply` — those reach AWS.

## Output → `reviews/`

Persist the findings to `reviews/audit-infra.md` (gitignored working notes — see [`reviews/README.md`](../../../reviews/README.md)), not only to chat. One finding per entry with a `[ ]` status box, grouped by severity. If that file already exists from a prior run, update it in place — flip resolved findings to `[x]` (with the fix commit) and keep `[~]` deferred items — instead of overwriting. The audit is otherwise read-only on the codebase; writing this one findings file is the allowed exception.
