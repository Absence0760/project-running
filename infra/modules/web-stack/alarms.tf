# CloudWatch alarms for the eight web Lambdas + the CloudFront distribution.
#
# All alarms route to the same SNS topic per env. Email subscribers are
# managed in Terraform via `var.alert_emails` (per-env tfvars) so a
# topic without a subscriber is impossible to ship — the audit/cost-
# controls Medium flagged that the previous "subscribe out of band"
# step was operationally fragile (an unsubscribed throttle alarm is
# functionally identical to no alarm).
#
# The first apply per address sends an opt-in confirmation email; the
# subscription stays in `pending_confirmation` until the recipient
# clicks the link. Subsequent applies are idempotent.

resource "aws_sns_topic" "alerts" {
  name = "${local.resource_prefix}-alerts"
  # Encrypt with the customer-managed key we already provision for
  # the Lambda env vars + log group. Closes Trivy AWS-0095 (no
  # encryption) and AWS-0136 (encryption not using CMK) in one
  # statement and keeps rotation under our control rather than AWS's.
  kms_master_key_id = aws_kms_key.secrets.arn
  tags              = var.tags
}

resource "aws_sns_topic_subscription" "alerts_email" {
  for_each  = toset(var.alert_emails)
  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = each.value
}

resource "aws_cloudwatch_metric_alarm" "lambda_errors" {
  alarm_name          = "${local.resource_prefix}-coach-lambda-errors"
  alarm_description   = "Coach Lambda 4xx/5xx error rate over 2% across two consecutive 5-min windows (10 min sustained)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  metric_query {
    id          = "errors_pct"
    expression  = "(errors / invocations) * 100"
    label       = "Error rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = aws_lambda_function.coach.function_name
      }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = aws_lambda_function.coach.function_name
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_p95_duration" {
  alarm_name          = "${local.resource_prefix}-coach-lambda-p95"
  alarm_description   = "Coach Lambda p95 duration >25 s across two consecutive 5-min windows (approaching the 30 s timeout)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 25000
  treat_missing_data  = "notBreaching"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p95"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  dimensions = {
    FunctionName = aws_lambda_function.coach.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "generate_route_lambda_errors" {
  alarm_name          = "${local.resource_prefix}-generate-route-lambda-errors"
  alarm_description   = "Generate-route Lambda 4xx/5xx error rate over 2% across two consecutive 5-min windows (10 min sustained). Usually the GraphHopper engine being unreachable."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  metric_query {
    id          = "errors_pct"
    expression  = "(errors / invocations) * 100"
    label       = "Error rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = aws_lambda_function.generate_route.function_name
      }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = aws_lambda_function.generate_route.function_name
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "generate_route_lambda_p95_duration" {
  alarm_name          = "${local.resource_prefix}-generate-route-lambda-p95"
  alarm_description   = "Generate-route Lambda p95 duration >12 s across two consecutive 5-min windows (approaching the 15 s timeout). Usually a slow / overloaded GraphHopper engine."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 12000
  treat_missing_data  = "notBreaching"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p95"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  dimensions = {
    FunctionName = aws_lambda_function.generate_route.function_name
  }
}

resource "aws_cloudwatch_log_metric_filter" "generate_route_engine_unreachable" {
  name           = "${local.resource_prefix}-generate-route-engine-unreachable"
  log_group_name = aws_cloudwatch_log_group.lambda_generate_route.name
  # `console.error('[generate-route] engine_unreachable')` from the Lambda when
  # handleGenerate returns 502. That 502 is a CLEAN handled response (the engine
  # is down / unreachable), NOT a Lambda throw, so the AWS/Lambda Errors metric
  # never sees it — and the client silently falls back to the worse in-browser
  # OSRM heuristic. Without this filter a GraphHopper outage degrades every user
  # with nobody paged. The pattern matches the tagged log shape so a future
  # rephrase doesn't silently break the alarm.
  pattern = "\"[generate-route] engine_unreachable\""

  metric_transformation {
    name          = "${local.resource_prefix}-generate-route-engine-unreachable-count"
    namespace     = "Threkir/GenerateRoute"
    value         = "1"
    default_value = "0"
  }
}
resource "aws_cloudwatch_metric_alarm" "generate_route_engine_unreachable" {
  alarm_name          = "${local.resource_prefix}-generate-route-engine-unreachable"
  alarm_description   = "GraphHopper is unreachable from the generate-route Lambda (>=5 engine_unreachable events in each of two consecutive 5-min windows). Route generation has silently degraded to the in-browser OSRM heuristic for all users. Check the GraphHopper Fly app."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"
  metric_name         = aws_cloudwatch_log_metric_filter.generate_route_engine_unreachable.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.generate_route_engine_unreachable.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# osrm-proxy mirrors generate-route's failure shape: a down OSRM engine is a
# CLEAN 502 (the builder degrades to straight-line segments), not a Lambda
# throw, so the Errors metric alone would sleep through an engine outage.
resource "aws_cloudwatch_metric_alarm" "osrm_proxy_lambda_errors" {
  alarm_name          = "${local.resource_prefix}-osrm-proxy-lambda-errors"
  alarm_description   = "Osrm-proxy Lambda 4xx/5xx error rate over 2% across two consecutive 5-min windows (10 min sustained)."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  metric_query {
    id          = "errors_pct"
    expression  = "(errors / invocations) * 100"
    label       = "Error rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = aws_lambda_function.osrm_proxy.function_name
      }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = aws_lambda_function.osrm_proxy.function_name
      }
    }
  }
}

# The p95 alarm generate-route carries, on the sibling the comment above calls
# its mirror. It was missing: the proxy shares generate-route's 15 s timeout and
# its clean-502 degradation, so a slow engine walks the duration toward the
# timeout while the error rate stays flat, the route builder quietly falls back
# to straight-line segments, and — because the distribution's SPA error fallback
# rewrites a Lambda-origin 403 into the shell at 200 — nothing downstream
# looks wrong either. The alarm is the only place that outage becomes visible.
resource "aws_cloudwatch_metric_alarm" "osrm_proxy_lambda_p95_duration" {
  alarm_name          = "${local.resource_prefix}-osrm-proxy-lambda-p95"
  alarm_description   = "Osrm-proxy Lambda p95 duration >12 s across two consecutive 5-min windows (approaching the 15 s timeout). Usually a slow / overloaded OSRM engine."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 12000
  treat_missing_data  = "notBreaching"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p95"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  dimensions = {
    FunctionName = aws_lambda_function.osrm_proxy.function_name
  }
}

resource "aws_cloudwatch_log_metric_filter" "osrm_proxy_engine_unreachable" {
  name           = "${local.resource_prefix}-osrm-proxy-engine-unreachable"
  log_group_name = aws_cloudwatch_log_group.lambda_osrm_proxy.name
  # `console.error('[osrm-proxy] engine_unreachable')` from the Lambda when
  # handleOsrmProxy returns 502 — same clean-502 shape as generate-route.
  pattern = "\"[osrm-proxy] engine_unreachable\""

  metric_transformation {
    name          = "${local.resource_prefix}-osrm-proxy-engine-unreachable-count"
    namespace     = "Threkir/OsrmProxy"
    value         = "1"
    default_value = "0"
  }
}
resource "aws_cloudwatch_metric_alarm" "osrm_proxy_engine_unreachable" {
  alarm_name          = "${local.resource_prefix}-osrm-proxy-engine-unreachable"
  alarm_description   = "The OSRM engine is unreachable from the osrm-proxy Lambda (>=5 engine_unreachable events in each of two consecutive 5-min windows). Route-builder snapping has silently degraded to straight-line segments for all users. Check the OSRM Fly app."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"
  metric_name         = aws_cloudwatch_log_metric_filter.osrm_proxy_engine_unreachable.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.osrm_proxy_engine_unreachable.metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# The share Lambdas keep serving a branded fallback card (HTTP 200 PNG /
# 404 HTML) when Supabase is unreachable — correct for never breaking a social
# unfurl, but it means a Supabase outage degrades EVERY card with no AWS/Lambda
# Errors metric to alarm on (the fallback is a returned response, not a throw).
# Each lookup helper (apps/web/src/lib/share/share_*_lookup.ts) logs a tagged
# `[share-<surface>] upstream_unreachable` line only on a real infra failure
# (Supabase error / throw), NOT on a clean not-found — this metric-filter +
# alarm pair keys off it, mirroring generate-route's engine_unreachable. One per
# share log group via for_each. /audit/infra N2 2026-07-02.
locals {
  share_log_groups = {
    run   = aws_cloudwatch_log_group.lambda_share_run.name
    route = aws_cloudwatch_log_group.lambda_share_route.name
    recap = aws_cloudwatch_log_group.lambda_share_recap.name
    badge = aws_cloudwatch_log_group.lambda_share_badge.name
    # The shared entity Lambda logs a per-surface tag ([share-event] /
    # [share-profile] / [share-club] / [share-race] / [share-session] /
    # [share-workout]) rather than a single [share-entity], so it gets one
    # metric filter per surface, all against its single log group, keeping
    # per-surface visibility.
    event   = aws_cloudwatch_log_group.lambda_share_entity.name
    profile = aws_cloudwatch_log_group.lambda_share_entity.name
    club    = aws_cloudwatch_log_group.lambda_share_entity.name
    race    = aws_cloudwatch_log_group.lambda_share_entity.name
    session = aws_cloudwatch_log_group.lambda_share_entity.name
    workout = aws_cloudwatch_log_group.lambda_share_entity.name
  }
}

resource "aws_cloudwatch_log_metric_filter" "share_upstream_unreachable" {
  for_each       = local.share_log_groups
  name           = "${local.resource_prefix}-share-${each.key}-upstream-unreachable"
  log_group_name = each.value
  pattern        = "\"[share-${each.key}] upstream_unreachable\""

  metric_transformation {
    name          = "${local.resource_prefix}-share-${each.key}-upstream-unreachable-count"
    namespace     = "Threkir/Share"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "share_upstream_unreachable" {
  for_each            = local.share_log_groups
  alarm_name          = "${local.resource_prefix}-share-${each.key}-upstream-unreachable"
  alarm_description   = "Share-${each.key} Lambda logged >=5 upstream_unreachable events in each of two consecutive 5-min windows — Supabase is unreachable from the share renderer and every ${each.key} unfurl has silently degraded to the branded fallback card. Check Supabase health."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 5
  treat_missing_data  = "notBreaching"
  metric_name         = aws_cloudwatch_log_metric_filter.share_upstream_unreachable[each.key].metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.share_upstream_unreachable[each.key].metric_transformation[0].namespace
  period              = 300
  statistic           = "Sum"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

resource "aws_cloudwatch_log_metric_filter" "coach_bypass_paywall" {
  name           = "${local.resource_prefix}-coach-bypass-paywall"
  log_group_name = aws_cloudwatch_log_group.lambda.name
  # `console.error('[coach] bypass_paywall_active …')` from the
  # handler. A single occurrence in production means the daily-cap
  # + cost gates are off for the session — billing emergency. The
  # filter pattern matches the tagged log shape so a future log-line
  # rephrase doesn't silently break the alarm. Audit/coach May 2026
  # Low #14.
  pattern = "\"[coach] bypass_paywall_active\""

  metric_transformation {
    name          = "${local.resource_prefix}-coach-bypass-paywall-count"
    namespace     = "Threkir/Coach"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "coach_bypass_paywall" {
  alarm_name          = "${local.resource_prefix}-coach-bypass-paywall"
  alarm_description   = "BYPASS_PAYWALL fired in the coach handler. In production this means the env gate failed and the daily cap + spend ceilings are off — billing emergency. /audit/coach Low #14."
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  threshold           = 1
  treat_missing_data  = "notBreaching"
  metric_name         = aws_cloudwatch_log_metric_filter.coach_bypass_paywall.metric_transformation[0].name
  namespace           = aws_cloudwatch_log_metric_filter.coach_bypass_paywall.metric_transformation[0].namespace
  period              = 60
  statistic           = "Sum"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags
}

# The five share Lambdas are homogeneous ENOUGH to share one alarm pair each:
# a 15 s timeout and a graceful degradation that returns HTTP 200/404 rather
# than throwing, so the Errors metric alone would sleep through a bad deploy.
# One error-rate + one p95 alarm apiece, generated with for_each and routed to
# the same SNS topic. A throttle alarm is lower-value here (reserved-
# concurrency-capped, buffered read surface) so it's omitted; the error-rate
# alarm is the signal that was missing — an erroring share Lambda otherwise
# breaks social unfurls with nobody paged. /audit/infra N1 2026-07-02.
#
# They are NOT identical, and this comment claimed they were: it said "the four
# share-card Lambdas (share-run/route/recap/badge) … 512 MB, SVG→PNG render"
# while the map below has carried `entity` since the shared entity-SSR Lambda
# landed. That one is 256 MB and HTML-only — no resvg, no og:image PNG — which
# is exactly why the p95 threshold below is a shared 12 s against the shared
# timeout rather than anything derived from the render budget.
locals {
  share_lambdas = {
    run    = aws_lambda_function.share_run.function_name
    route  = aws_lambda_function.share_route.function_name
    recap  = aws_lambda_function.share_recap.function_name
    badge  = aws_lambda_function.share_badge.function_name
    entity = aws_lambda_function.share_entity.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "share_lambda_errors" {
  for_each            = local.share_lambdas
  alarm_name          = "${local.resource_prefix}-share-${each.key}-lambda-errors"
  alarm_description   = "Share-${each.key} Lambda 4xx/5xx error rate over 2% across two consecutive 5-min windows (10 min sustained). Social unfurl cards are failing."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 2
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  metric_query {
    id          = "errors_pct"
    expression  = "(errors / invocations) * 100"
    label       = "Error rate (%)"
    return_data = true
  }

  metric_query {
    id = "errors"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = each.value
      }
    }
  }

  metric_query {
    id = "invocations"
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = each.value
      }
    }
  }
}

resource "aws_cloudwatch_metric_alarm" "share_lambda_p95_duration" {
  for_each            = local.share_lambdas
  alarm_name          = "${local.resource_prefix}-share-${each.key}-lambda-p95"
  alarm_description   = "Share-${each.key} Lambda p95 duration >12 s across two consecutive 5-min windows (approaching the 15 s timeout). Usually a slow Supabase read or resvg render pressure on the 512 MB budget."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 12000
  treat_missing_data  = "notBreaching"
  metric_name         = "Duration"
  namespace           = "AWS/Lambda"
  period              = 300
  extended_statistic  = "p95"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  dimensions = {
    FunctionName = each.value
  }
}

# ─────────────────── Distribution-level error rates ───────────────────
#
# This file's own first line said "alarms for the coach Lambda + the CloudFront
# distribution" and apps/web/deployment.md listed a 4xx and a 5xx distribution
# alarm under "CloudWatch alarms (wired by the web-stack module)". Neither
# existed: every alarm here was per-Lambda, so the observability bar that
# document sets for v1 — "someone gets paged when the site is down" — was met by
# nothing. A per-Lambda alarm cannot see a distribution serving errors from S3,
# a broken behaviour ordering, or an origin the OAC has stopped signing for.
#
# Rate metrics, not counts: CloudFront publishes 4xxErrorRate / 5xxErrorRate as
# percentages of requests, so the alarm does not need a traffic-volume baseline
# to be meaningful, and `notBreaching` on missing data keeps a quiet preview env
# out of ALARM.
#
# CloudFront metrics are published ONLY in us-east-1, under a fixed
# `Region = "Global"` dimension. These use the module's default provider rather
# than the aws.us_east_1 alias because a CloudWatch alarm's actions must live in
# the alarm's own region and aws_sns_topic.alerts is created by the default
# provider. Both are us-east-1 today (infra/README.md § Region); moving the
# stack's primary region is already a manual multi-file edit, and this is one
# more file it has to touch.
resource "aws_cloudwatch_metric_alarm" "cloudfront_4xx" {
  alarm_name          = "${local.resource_prefix}-cloudfront-4xx"
  alarm_description   = "CloudFront 4xx rate over ${var.cloudfront_4xx_alarm_threshold}% across two consecutive 5-min windows. Catches mass auth failures, a broken behaviour ordering, or an SPA fallback misconfiguration."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = var.cloudfront_4xx_alarm_threshold
  treat_missing_data  = "notBreaching"
  metric_name         = "4xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  dimensions = {
    DistributionId = aws_cloudfront_distribution.this.id
    Region         = "Global"
  }
}

resource "aws_cloudwatch_metric_alarm" "cloudfront_5xx" {
  alarm_name          = "${local.resource_prefix}-cloudfront-5xx"
  alarm_description   = "CloudFront 5xx rate over ${var.cloudfront_5xx_alarm_threshold}% across two consecutive 5-min windows. The site is failing for a share of viewers, whichever origin is at fault."
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = var.cloudfront_5xx_alarm_threshold
  treat_missing_data  = "notBreaching"
  metric_name         = "5xxErrorRate"
  namespace           = "AWS/CloudFront"
  period              = 300
  statistic           = "Average"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  dimensions = {
    DistributionId = aws_cloudfront_distribution.this.id
    Region         = "Global"
  }
}

# ─────────────────── Throttles ───────────────────
#
# A throttled invocation increments Throttles, never Errors, so none of the
# error-rate alarms above can see one. Declared for the three functions whose
# reserved concurrency is a deliberate ceiling on spend or on an engine's load —
# hitting it must be loud, which is coach's rationale applied to its two
# siblings; apps/web/deployment.md already listed generate-route's. The five
# share Lambdas keep the omission the block below records: concurrency-capped
# buffered reads whose degradation is already covered by their upstream alarms.
locals {
  throttle_alarms = {
    coach          = aws_lambda_function.coach.function_name
    generate-route = aws_lambda_function.generate_route.function_name
    osrm-proxy     = aws_lambda_function.osrm_proxy.function_name
  }
}

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  for_each          = local.throttle_alarms
  alarm_name        = "${local.resource_prefix}-${each.key}-lambda-throttles"
  alarm_description = "${each.key} Lambda throttled (≥${var.lambda_throttle_alarm_threshold} throttles across two 5-min windows). Concurrent execution cap is being hit."
  # Threshold parameterised per-env: preview keeps the default 5
  # (single noisy demo session can briefly touch the cap and clear
  # inside 60 s — alarming on that would be pure noise). Prod should
  # set it to 1 so a single throttle pages immediately — the reserved
  # concurrency is the cost ceiling, hitting it must be a loud signal.
  # /audit/all cost-controls Medium 2026-05-07.
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = var.lambda_throttle_alarm_threshold
  treat_missing_data  = "notBreaching"
  metric_name         = "Throttles"
  namespace           = "AWS/Lambda"
  period              = 300
  statistic           = "Sum"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]
  tags                = var.tags

  dimensions = {
    FunctionName = each.value
  }
}
