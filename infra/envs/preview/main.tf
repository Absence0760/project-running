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

  # Tight cap on preview — single-digit concurrency is plenty for
  # smoke tests and PR review and bounds Anthropic spend if a script
  # accidentally hammers preview.
  lambda_reserved_concurrency = 5

  secrets_file     = fileexists(local.secrets_path) ? local.secrets_path : null
  extra_lambda_env = var.extra_lambda_env

  tags = {
    project = "runonward"
    env     = "preview"
    managed = "terraform"
  }
}
