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
  description = "Optional NON-SECRET extras like COACH_PROVIDER, OPENAI_BASE_URL. Surfaced into the Lambda env unencrypted and visible in `terraform plan` — never route a real secret through here; put secrets in the sops file (var.secrets_file) instead."
  type        = map(string)
  default     = {}
}

variable "secrets_file" {
  description = "Path to this env's sops-encrypted secrets file. Defaults to ../infra-secrets/running/prod.sops.yaml — the PRIVATE estate repo (Absence0760/infra-secrets) cloned as a sibling of this repo. NEVER point this inside this public repo (ciphertext in public history leaks KMS-ARN metadata + secret key names). Empty string = use the default path."
  type        = string
  default     = ""
}

variable "graphhopper_url" {
  description = "Base URL of the self-hosted GraphHopper engine the generate-route Lambda calls for round_trip route generation (e.g. 'https://graphhopper.internal.threkir.com'). Non-secret. Empty string leaves the endpoint unconfigured (501) and the client falls back to the OSRM heuristic."
  type        = string
  default     = ""
}

variable "graph_cycle_url" {
  description = "Base URL of the self-hosted graph_cycle map sidecar the generate-route Lambda tries FIRST for v3 graph-cycle loop generation (e.g. 'https://graph-cycle.fly.dev'). Non-secret; the GRAPH_CYCLE_API_KEY shared secret comes from sops. Empty string leaves graph-cycle unconfigured so the handler serves round_trip — no regression."
  type        = string
  default     = ""
}

variable "monthly_budget_limit_usd" {
  description = "Hard ceiling for the AWS Budgets account-wide monthly cost alert (in USD). Notifications fire at 50 % ACTUAL, 100 % ACTUAL, and 100 % FORECASTED. Pick a few times the projected baseline so the 50 % alert doesn't cry wolf every month. Rock-bottom AWS baseline is ~$10/mo (WAF ~$7 + KMS $1 + Route 53 zone $0.50 + alarms ~$1.50), so the default 30 keeps the 50 % threshold ($15) clear of it while still catching a ~3x runaway. Raise toward ~$150 when moving to the full launch profile (~$70/mo baseline per docs/ops/deployment.md)."
  type        = number
  default     = 30
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
