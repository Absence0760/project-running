variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "apex_domain" {
  type    = string
  default = "threkir.com"
}

variable "preview_subdomain" {
  description = "Subdomain prefix the preview env serves at."
  type        = string
  default     = "preview"
}

variable "public_supabase_url" {
  description = "Preview Supabase REST URL — typically the same as prod, OR a separate preview Supabase project if you want isolation."
  type        = string
}

variable "public_supabase_anon_key" {
  type      = string
  sensitive = true
}

variable "extra_lambda_env" {
  type    = map(string)
  default = {}
}

# Email subscribers for the preview env's CloudWatch alarms (Lambda
# throttling + 5xx error rate). Without subscribers the alarms fire
# into an SNS topic nobody reads — a hit Lambda concurrency cap on
# preview goes silent and the symptom only shows up in the next
# round of e2e tests. The default is intentionally non-empty (mirror
# prod's discipline) so a `terraform apply` on a fresh preview env
# must explicitly opt out of alarms via `["nobody@example.com"]` if
# the operator really doesn't want them. /audit/cost-controls May 2026
# closeout — prod had this validation; preview was the lone outlier.
variable "alert_emails" {
  description = "Email addresses to subscribe to preview CloudWatch alarms (Lambda throttling, 5xx rate). At least one required — empty list means alarms fire silently."
  type        = list(string)

  validation {
    condition     = length(var.alert_emails) > 0
    error_message = "Provide at least one address in alert_emails — preview alarms must page somewhere (even if it's the same single-developer inbox prod uses)."
  }

  validation {
    condition = alltrue([
      for e in var.alert_emails :
      !endswith(e, "@example.com") && !startswith(e, "you@")
    ])
    error_message = "alert_emails contains an @example.com / you@ placeholder — replace with a real address."
  }
}
