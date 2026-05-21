variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "apex_domain" {
  description = "Should match the apex configured in `infra/dns`."
  type        = string
  default     = "threkir.com"
}

variable "public_supabase_url" {
  description = "Production Supabase REST URL. Once `api.threkir.com` is wired, switch to that."
  type        = string
}

variable "public_supabase_anon_key" {
  description = "Supabase publishable key (NOT service-role)."
  type        = string
  sensitive   = true
}

variable "extra_lambda_env" {
  description = "Optional extras like COACH_PROVIDER, OPENAI_BASE_URL."
  type        = map(string)
  default     = {}
}

variable "monthly_budget_limit_usd" {
  description = "Hard ceiling for the AWS Budgets account-wide monthly cost alert (in USD). Notifications fire at 50 % ACTUAL, 100 % ACTUAL, and 100 % FORECASTED. Pick something a few times the projected baseline (~$70/mo at launch per docs/deployment.md)."
  type        = number
  default     = 200
}

variable "budget_alert_emails" {
  description = "Email addresses that receive every budget notification. At least one is required; the budget resource silently does nothing useful otherwise."
  type        = list(string)
  validation {
    condition     = length(var.budget_alert_emails) > 0
    error_message = "Provide at least one address in budget_alert_emails — a budget with no subscribers is just an expensive no-op."
  }
  validation {
    condition = alltrue([
      for e in var.budget_alert_emails :
      !can(regex("(?i)@example\\.com$|^you@", e))
    ])
    error_message = "budget_alert_emails contains an @example.com / you@ placeholder — replace with a real address. /audit/all cost-controls Low caught a copied-from-example fall-through."
  }
}

variable "alert_emails" {
  description = "Email addresses subscribed to the SNS topic that the Lambda error / p95 / throttle CloudWatch alarms route to. At least one is required for prod — the audit/cost-controls Medium called out that the throttle alarm with no subscribers is functionally identical to no alarm. Each address gets an opt-in confirmation email on first apply."
  type        = list(string)
  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "Provide at least one address in alert_emails — prod alarms must page somewhere."
  }
  validation {
    condition = alltrue([
      for e in var.alert_emails :
      !can(regex("(?i)@example\\.com$|^you@", e))
    ])
    error_message = "alert_emails contains an @example.com / you@ placeholder — replace with a real address."
  }
}
