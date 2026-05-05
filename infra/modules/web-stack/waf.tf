# AWS WAF v2 — per-IP rate limit on the coach Lambda.
#
# CloudFront's /api/coach/* behaviour fronts the only path that costs
# money to serve. The per-user daily cap in TIER_LIMITS.free.dailyLimit
# bounds an authenticated user's spend, but a stolen-token-ring + the
# Lambda concurrency cap is the second line of defence; this WAF rule
# is the third — "you can't even reach the Lambda 100 times in 5 min
# from one IP". Static-asset traffic is unaffected because the
# scope-down statement filters to /api/coach* before the rate counter
# applies.
#
# CLOUDFRONT-scope WAF resources must live in us-east-1 regardless of
# where the rest of the stack runs. The module's required_providers
# block already declares the aws.us_east_1 alias for exactly this.

resource "aws_wafv2_web_acl" "coach" {
  count    = var.waf_enabled ? 1 : 0
  provider = aws.us_east_1

  name        = "${local.resource_prefix}-coach"
  description = "Per-IP rate limit on /api/coach to bound denial-of-wallet bursts."
  scope       = "CLOUDFRONT"
  tags        = var.tags

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit-coach"
    priority = 1

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.waf_rate_limit
        aggregate_key_type = "IP"

        scope_down_statement {
          byte_match_statement {
            positional_constraint = "STARTS_WITH"
            search_string         = "/api/coach"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.resource_prefix}-rate-limit-coach"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.resource_prefix}-coach-acl"
    sampled_requests_enabled   = true
  }
}
