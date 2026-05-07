# CloudWatch alarms for the coach Lambda + the CloudFront distribution.
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
  tags = var.tags
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

resource "aws_cloudwatch_metric_alarm" "lambda_throttles" {
  alarm_name        = "${local.resource_prefix}-coach-lambda-throttles"
  alarm_description = "Coach Lambda throttled (≥${var.lambda_throttle_alarm_threshold} throttles across two 5-min windows). Concurrent execution cap is being hit."
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
    FunctionName = aws_lambda_function.coach.function_name
  }
}
