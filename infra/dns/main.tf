# Hosted zone for the apex domain + the ACM cert that CloudFront
# distributions in `envs/*` consume.
#
# CloudFront only reads certs from `us-east-1`, regardless of where
# the rest of the stack runs. Two AWS providers, aliased by region.
#
# One stack, both envs share. Outputs are consumed via
# `terraform_remote_state` from `envs/<env>/main.tf`.

provider "aws" {
  region = var.aws_region
}

provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# ─────────────────── Route 53 ───────────────────

resource "aws_route53_zone" "apex" {
  name = var.apex_domain
  tags = var.tags
}

# ─────────────────── ACM cert (us-east-1, for CloudFront) ───────────────────

resource "aws_acm_certificate" "apex" {
  provider                  = aws.us_east_1
  domain_name               = var.apex_domain
  subject_alternative_names = var.subject_alternative_names
  validation_method         = "DNS"
  tags                      = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "cert_validation" {
  for_each = {
    for dvo in aws_acm_certificate.apex.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  zone_id = aws_route53_zone.apex.zone_id
  name    = each.value.name
  type    = each.value.type
  records = [each.value.record]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "apex" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.apex.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]
}
