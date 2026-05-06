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
#   - The `secrets.enc.yaml` file in this directory does NOT exist yet
#     on the very first apply. The KMS key is created here, then the
#     user encrypts a secrets file against it, then re-applies. See
#     the README at `infra/README.md` for the full first-deploy flow.

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
    bucket = "runonward-tfstate"
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
    bucket = "runonward-tfstate"
    key    = "github-oidc/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  secrets_path = "${path.module}/secrets.enc.yaml"
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

  acm_certificate_arn = data.terraform_remote_state.dns.outputs.certificate_arn
  route53_zone_id     = data.terraform_remote_state.dns.outputs.zone_id

  public_supabase_url      = var.public_supabase_url
  public_supabase_anon_key = var.public_supabase_anon_key

  # Caps worst-case concurrency. 50 = ~50 simultaneous coach turns,
  # which at ~3k input + ~1k output × Anthropic pricing puts the
  # absolute burst spend at a known ceiling. Raise once we have real
  # traffic data.
  lambda_reserved_concurrency = 50

  # Null on first apply (file doesn't exist yet). The user encrypts a
  # secrets file against the KMS key created here, then re-applies and
  # the Lambda gets the real env vars.
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
