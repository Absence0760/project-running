# AWS Budgets — account-wide spend ceiling.
#
# Budgets are global to the AWS account, not scoped to a stack. We
# declare them once from the prod env so a fresh apply against a new
# account always wires them; preview never declares its own (would
# duplicate). The notifications fire to every address in
# var.budget_alert_emails so a runaway coach Lambda or an egress attack
# can't quietly run for a month before anyone notices.
#
# Three thresholds:
#   - 50 % ACTUAL    → "you're halfway through the month's allowance"
#   - 100 % ACTUAL   → "the budget is now blown for this month"
#   - 100 % FORECAST → "current burn rate projects past the limit"
#
# The forecast threshold is the one that actually catches a runaway
# early — the ACTUAL thresholds only fire after the spend lands on the
# bill, which is up to 24 h after the request.
#
# IAM: the user/role running `terraform apply` needs `budgets:*`.
# Identity Center users with AdministratorAccess have it; the GitHub
# OIDC deploy role does not — these resources are intended to be
# applied locally, not from CI.

resource "aws_budgets_budget" "monthly" {
  name         = "runonward-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_limit_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = var.budget_alert_emails
  }
}
