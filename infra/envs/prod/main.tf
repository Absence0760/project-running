# Prod web stack root module.
#
# Run from `infra/envs/prod/`:
#   terraform init
#   terraform apply
#
# First-apply expectations:
#   - `infra/bootstrap` has been applied (S3 state bucket — locking is
#     S3-native via `use_lockfile = true`, so no DDB table is needed)
#   - `infra/dns` has been applied (hosted zone + ACM cert)
#   - The prod secrets file does NOT exist yet on the very first apply.
#     The KMS key is created here, then the operator encrypts a secrets
#     file against it IN THE PRIVATE ESTATE REPO (../infra-secrets, NOT
#     this public repo), then re-applies. See `infra/README.md` for the
#     full first-deploy flow.

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# Read DNS outputs (zone ID, cert ARN) via remote state — keeps the
# wiring explicit and side-steps any chicken-and-egg with var values.
data "terraform_remote_state" "dns" {
  backend = "s3"
  config = {
    bucket = "threkir-tfstate"
    key    = "dns/terraform.tfstate"
    region = "us-east-1"
  }
}

# Read the OIDC deploy role ARNs so the KMS key policy can authorise
# the GitHub Actions runner to call kms:Decrypt at terraform-apply
# time (sops_file data source needs it). Audit pass 3 found this
# variable was added in pass 2 but never wired through.
data "terraform_remote_state" "github_oidc" {
  backend = "s3"
  config = {
    bucket = "threkir-tfstate"
    key    = "github-oidc/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  # Production secrets live in the PRIVATE estate repo Absence0760/infra-secrets
  # (../infra-secrets), one subdir per project — NOT in this PUBLIC repo. The
  # ciphertext is encrypted with this env's KMS key (created below) and consumed
  # in-memory by the sops_file data source at apply time. The default assumes the
  # estate repo is cloned as a sibling of this one; override `secrets_file`
  # (TF_VAR_secrets_file) if your clone lives elsewhere. See infra/README.md and
  # decisions.md §53.
  secrets_path = var.secrets_file != "" ? var.secrets_file : "${path.module}/../../../../infra-secrets/running/prod.sops.yaml"
}

module "web" {
  source = "../../modules/web-stack"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  env         = "prod"
  domain_name = var.apex_domain
  aliases     = ["www.${var.apex_domain}"]

  # Prod serves both www + apex on this distribution; 301 www -> apex so
  # search engines consolidate onto one canonical host (SEO). Preview
  # has no www alias, so it leaves this at the default false.
  redirect_www_to_apex = true

  acm_certificate_arn = data.terraform_remote_state.dns.outputs.certificate_arn
  route53_zone_id     = data.terraform_remote_state.dns.outputs.zone_id

  public_supabase_url      = var.public_supabase_url
  public_supabase_anon_key = var.public_supabase_anon_key
  public_site_url          = "https://${var.apex_domain}"

  # Caps worst-case concurrency. 20 = ~20 simultaneous coach turns,
  # which at ~3k input + ~1k output × Anthropic pricing puts the
  # absolute burst spend at a known ceiling. Tightened for a
  # cost-minimized launch; raise once we have real traffic data.
  # Var-driven (default 20) so a tfvars override can set -1 while the
  # account's Lambda concurrency quota is still the new-account 10 —
  # reservations need >=10 left unreserved, so under a 10 pool ANY
  # reservation is rejected (and the 10-wide pool is itself the
  # tighter bill cap until the quota raise lands).
  lambda_reserved_concurrency = var.lambda_reserved_concurrency

  # Self-hosted GraphHopper engine URL for server-side route generation.
  # Non-secret (an internal engine URL), so it's a plain var, not sops.
  # When empty the generate endpoint returns 501 and the client falls
  # back to the OSRM heuristic.
  graphhopper_url = var.graphhopper_url

  # graph_cycle map sidecar — the v3 graph-cycle generator the Lambda tries
  # FIRST. When empty the handler skips it and serves round_trip (no regression).
  graph_cycle_url = var.graph_cycle_url

  # Self-hosted OSRM engine URL for the route builder's server-side
  # waypoint snapping/routing proxy (issue #198 — server-only, the browser
  # only ever calls /api/routes/osrm). Non-secret. When empty the proxy
  # returns 501 and the builder degrades to straight-line segments.
  osrm_url = var.osrm_url

  # Caps the generate-route Lambda's concurrency. Each invocation fans
  # out several round_trip calls at the GraphHopper engine, so this is
  # the engine's load ceiling. 25 is comfortable for launch traffic;
  # raise once real usage is observed. Var-driven for the same
  # quota-pending override as lambda_reserved_concurrency above.
  generate_route_reserved_concurrency = var.generate_route_reserved_concurrency

  # Same load-ceiling idea for the osrm-proxy Lambda — each invocation is
  # one snapping/routing round trip at the self-hosted OSRM engine.
  osrm_proxy_reserved_concurrency = var.osrm_proxy_reserved_concurrency

  # Prod tightens the coach WAF per-IP rate limit below the module
  # default (100). A free user's coach cap is 2/day and a pro's 10/day
  # (TIER_LIMITS in apps/web/src/lib/coach/types.ts), so 30 req / 5 min
  # from a single IP is already far past any legitimate pattern — even a
  # shared NAT/CGNAT egress — while shrinking the denial-of-wallet burst
  # surface ~3x versus the default. generate-route keeps the module
  # default (100): it hits the self-hosted engine, not a paid API, and
  # is concurrency-capped separately.
  waf_rate_limit = 30

  # Email subscribers for the per-env SNS alerts topic. Validated as
  # RFC-shaped in the module — the validation rejects @example.com
  # placeholders so a copy-pasted tfvars can't slip an alarm into the
  # void. /audit/all cost-controls Medium 2026-05-07.
  alert_emails = var.alert_emails

  # Prod tightens the Lambda throttle alarm: a single throttle pages
  # immediately. The reserved concurrency cap is the cost ceiling and
  # hitting it must not be a quiet event. Preview keeps the default 5
  # (noisy demo traffic).
  lambda_throttle_alarm_threshold = 1

  # Null on first apply (the external secrets file doesn't exist yet). The
  # operator encrypts ../infra-secrets/running/prod.sops.yaml against the KMS key
  # created here, then re-applies and the Lambda gets the real env vars.
  secrets_file     = fileexists(local.secrets_path) ? local.secrets_path : null
  extra_lambda_env = var.extra_lambda_env

  # Lets the prod deploy role decrypt sops at `terraform apply` time
  # from the GitHub Actions runner. Without this, only the AWS
  # account root could re-apply the stack post first-deploy.
  kms_decrypt_principal_arn = data.terraform_remote_state.github_oidc.outputs.deploy_role_arn_prod

  # PascalCase to match the bootstrap + github-oidc stacks; AWS treats
  # tag keys as case-sensitive so a single Cost Explorer / Resource
  # Groups query can group across all run-app resources.
  tags = {
    Project     = "run-app"
    Stack       = "web"
    Environment = "prod"
    ManagedBy   = "terraform"
  }
}
