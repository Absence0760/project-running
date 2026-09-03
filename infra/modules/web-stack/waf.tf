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

# ── Encoded spellings ──
#
# Every scope-down below matches `uri_path` with STARTS_WITH, and WAF does
# NOT decode that field, while CloudFront's own behaviour matching normalises
# independently. Two matchers, two normalisations — so any encoded spelling
# CloudFront resolves to the behaviour but WAF does not resolve to the prefix
# reaches the Lambda with the per-IP cap NOT applied, on the only three paths
# on this distribution that cost money or engine CPU to serve. Each scope-down
# therefore carries a URL_DECODE transformation at priority 1 beside the NONE
# at 0.
#
# That was added WITHOUT a live measurement, deliberately: whether CloudFront
# decodes before behaviour matching is a fact about the edge and this repo
# holds no AWS credentials by design. It is safe anyway because the failure
# direction is one-way. On a search string containing no `%`, URL_DECODE can
# only ADD matches — decoding replaces `%XX` with a single byte and never
# lengthens, so a raw path whose first ten characters are already `/api/coach`
# still has them afterwards. The transformation is a strict widening of a RATE
# LIMIT, never of an allow/deny. If CloudFront turns out not to decode either,
# the cost is that WAF counts a request the edge was going to 404 anyway; if
# it does decode, the gap closes. Being wrong here cannot let anything through.
#
# LOWERCASE is deliberately NOT added: CloudFront path patterns are
# case-sensitive, so `/API/coach` genuinely does not route to the Lambda and
# matching it would only rate-limit a 404. Double encoding (`%2563oach`)
# survives one decode and is out of scope for the same reason — CloudFront
# does not double-decode either. decisions § 1023.

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
        limit                 = var.waf_rate_limit
        aggregate_key_type    = "IP"
        evaluation_window_sec = 300

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

            # See "Encoded spellings" in the file header.
            text_transformation {
              priority = 1
              type     = "URL_DECODE"
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

  # Second rate-based rule on /api/routes/generate*. Each generate call
  # fans out several round_trip requests to the self-hosted GraphHopper
  # engine, so an unthrottled IP could pin the engine's CPU. The
  # per-IP cap here is the engine's denial-of-service backstop —
  # legitimate use is a handful of generations per session, nowhere
  # near var.waf_generate_route_rate_limit in a 5-min window.
  rule {
    name     = "rate-limit-generate-route"
    priority = 2

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = var.waf_generate_route_rate_limit
        aggregate_key_type    = "IP"
        evaluation_window_sec = 300

        scope_down_statement {
          byte_match_statement {
            positional_constraint = "STARTS_WITH"
            search_string         = "/api/routes/generate"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }

            # See "Encoded spellings" in the file header.
            text_transformation {
              priority = 1
              type     = "URL_DECODE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.resource_prefix}-rate-limit-generate-route"
      sampled_requests_enabled   = true
    }
  }

  # Third rate-based rule on /api/routes/osrm*. The proxy fronts the
  # self-hosted OSRM engine and requires a signed-in user, but the WAF cap
  # is the pre-auth backstop: it stops a scripted client (or a stolen JWT)
  # from using the proxy as a free routing relay or pinning the engine.
  # Interactive route-building legitimately issues tens of requests per
  # session, so the limit sits well above the coach/generate caps.
  rule {
    name     = "rate-limit-osrm-proxy"
    priority = 3

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit                 = var.waf_osrm_proxy_rate_limit
        aggregate_key_type    = "IP"
        evaluation_window_sec = 300

        scope_down_statement {
          byte_match_statement {
            positional_constraint = "STARTS_WITH"
            search_string         = "/api/routes/osrm"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "NONE"
            }

            # See "Encoded spellings" in the file header.
            text_transformation {
              priority = 1
              type     = "URL_DECODE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.resource_prefix}-rate-limit-osrm-proxy"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.resource_prefix}-coach-acl"
    sampled_requests_enabled   = true
  }
}
