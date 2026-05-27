provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

data "terraform_remote_state" "dns" {
  backend = "s3"
  config = {
    bucket = "runonward-tfstate"
    key    = "dns/terraform.tfstate"
    region = "us-east-1"
  }
}

# Read the OIDC deploy role ARN — see envs/prod/main.tf for rationale.
data "terraform_remote_state" "github_oidc" {
  backend = "s3"
  config = {
    bucket = "runonward-tfstate"
    key    = "github-oidc/terraform.tfstate"
    region = "us-east-1"
  }
}

locals {
  domain_name  = "${var.preview_subdomain}.${var.apex_domain}"
  secrets_path = "${path.module}/secrets.enc.yaml"
}

module "web" {
  source = "../../modules/web-stack"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  env         = "preview"
  domain_name = local.domain_name
  aliases     = []

  acm_certificate_arn = data.terraform_remote_state.dns.outputs.certificate_arn
  route53_zone_id     = data.terraform_remote_state.dns.outputs.zone_id

  public_supabase_url      = var.public_supabase_url
  public_supabase_anon_key = var.public_supabase_anon_key
  public_site_url          = "https://${local.domain_name}"

  # Tight cap on preview — single-digit concurrency is plenty for
  # smoke tests and PR review and bounds Anthropic spend if a script
  # accidentally hammers preview.
  lambda_reserved_concurrency = 5

  # Explicit rather than module-default so a future module-default
  # change doesn't silently shift preview's throttle-alarm
  # sensitivity. 5 throttles in the 5-min eval window is enough to
  # rule out a one-off concurrency blip but cheap enough that real
  # abuse fires the alarm fast. /audit/cost-controls May 2026.
  lambda_throttle_alarm_threshold = 5

  # SNS subscribers for the Lambda-throttle + 5xx alarms. Without
  # this wire preview alarms fired into an empty SNS topic — a hit
  # concurrency cap on a fresh preview env went silent. Validated
  # non-empty + placeholder-rejected in variables.tf.
  alert_emails = var.alert_emails

  secrets_file     = fileexists(local.secrets_path) ? local.secrets_path : null
  extra_lambda_env = var.extra_lambda_env

  kms_decrypt_principal_arn = data.terraform_remote_state.github_oidc.outputs.deploy_role_arn_preview

  # PascalCase to match the other stacks. See envs/prod/main.tf for
  # rationale.
  tags = {
    Project     = "run-app"
    Stack       = "web"
    Environment = "preview"
    ManagedBy   = "terraform"
  }
}
