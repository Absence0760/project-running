variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "apex_domain" {
  description = "Should match the apex configured in `infra/dns`."
  type        = string
  default     = "runonward.com"
}

variable "public_supabase_url" {
  description = "Production Supabase REST URL. Once `api.runonward.com` is wired, switch to that."
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
}
