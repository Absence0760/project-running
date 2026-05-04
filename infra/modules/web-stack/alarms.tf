# CloudWatch alarms for the coach Lambda + the CloudFront distribution.
#
# All alarms route to the same SNS topic per env. Subscribe an email
# address (or PagerDuty endpoint) to the topic out-of-band; the alarm
# definitions themselves stay in Terraform.

resource "aws_sns_topic" "alerts" {
  name = "${local.resource_prefix}-alerts"
  tags = var.tags
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
  alarm_description = "Coach Lambda throttled (≥5 throttles across two 5-min windows). Concurrent execution cap is being hit."
  # Sustained signal, not a single-data-point trigger. Preview's
  # reserved concurrency is 5; a single noisy demo session can briefly
  # touch the cap and clear inside 60 s — alarming on that would be
  # pure noise. Two consecutive 5-min periods at ≥5 throttles is real.
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  threshold           = 5
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
