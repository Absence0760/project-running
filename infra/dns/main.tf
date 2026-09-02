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

# Baseline tags for every taggable resource in this stack, matching the shape
# `bootstrap` and `github-oidc` use. AWS treats tag keys as case-sensitive, so a
# resource carrying only the caller's `var.tags` is absent from any Cost
# Explorer or Resource Groups query that groups by `Stack` — which is the
# breakage `bootstrap/main.tf` records having already hit once, and which the
# ACM cert below was silently reproducing.
locals {
  dns_tags = merge(
    {
      Project   = "run-app"
      Stack     = "dns"
      ManagedBy = "terraform"
    },
    var.tags,
  )
}

# ─────────────────── Route 53 ───────────────────

resource "aws_route53_zone" "apex" {
  name = var.apex_domain
  tags = local.dns_tags

  # Destroying the hosted zone wipes every NS-delegation chain
  # anchored at the registrar — recovery requires updating NS at the
  # registrar within the SOA TTL window. prevent_destroy forces a
  # manual `terraform state rm` first.
  lifecycle {
    prevent_destroy = true
  }
}

# ─────────────────── ACM cert (us-east-1, for CloudFront) ───────────────────

locals {
  effective_sans = var.subject_alternative_names != null ? var.subject_alternative_names : [
    "www.${var.apex_domain}",
    "preview.${var.apex_domain}",
  ]
}

resource "aws_acm_certificate" "apex" {
  provider                  = aws.us_east_1
  domain_name               = var.apex_domain
  subject_alternative_names = local.effective_sans
  validation_method         = "DNS"
  tags                      = local.dns_tags

  # Destroying the cert breaks CloudFront → DNS for both envs until
  # ACM revalidates (~30 min after re-issue + DNS propagation).
  # `create_before_destroy` already mitigates rotation-driven
  # destruction; `prevent_destroy` blocks `terraform destroy` on the
  # whole stack from taking the cert. The two are compatible.
  lifecycle {
    create_before_destroy = true
    prevent_destroy       = true
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

# ─────────────────── Email sender authentication ───────────────────
# DKIM / SPF / MX / DMARC for outbound mail (Resend). Values live in
# terraform.tfvars so a DR rebuild restores deliverability — a record
# added by hand in the console would silently vanish on rebuild.

resource "aws_route53_record" "email_auth" {
  for_each = var.email_auth_records

  zone_id = aws_route53_zone.apex.zone_id
  name    = each.value.name == "" ? var.apex_domain : "${each.value.name}.${var.apex_domain}"
  type    = each.value.type
  ttl     = each.value.ttl
  records = each.value.records
}

resource "aws_acm_certificate_validation" "apex" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.apex.arn
  validation_record_fqdns = [for r in aws_route53_record.cert_validation : r.fqdn]

  # Pair with create_before_destroy on the cert itself — when SANs
  # change, the validation goes through the new cert before the old
  # one is destroyed, so CloudFront never references a cert without
  # an attached validation.
  lifecycle {
    create_before_destroy = true
  }
}

# ─────────────────── Live spectator hub (Fly.io) ───────────────────
# live.threkir.com is the Go live hub (apps/job_worker) on Fly. TLS
# terminates at Fly's edge with a cert issued by `flyctl certs add`,
# not ACM, so a plain CNAME to the Fly app hostname is the whole
# integration — no SAN change on the CloudFront cert above.

resource "aws_route53_record" "live_hub" {
  zone_id = aws_route53_zone.apex.zone_id
  name    = "live.${var.apex_domain}"
  type    = "CNAME"
  ttl     = 300
  records = ["threkir-worker.fly.dev"]
}
