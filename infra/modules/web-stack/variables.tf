variable "env" {
  description = "Environment name — used as a suffix on every resource. e.g. 'prod', 'preview'."
  type        = string
  validation {
    condition     = contains(["prod", "preview"], var.env)
    error_message = "env must be 'prod' or 'preview'."
  }
}

variable "domain_name" {
  description = "Public domain for this env's CloudFront distribution. e.g. 'runonward.app' for prod, 'preview.runonward.app' for preview."
  type        = string
}

variable "aliases" {
  description = "Additional CloudFront aliases (e.g. ['www.runonward.app'] for prod). The cert in `acm_certificate_arn` must cover all of these."
  type        = list(string)
  default     = []
}

variable "acm_certificate_arn" {
  description = "ACM cert ARN in us-east-1, covering domain_name + aliases. Output of the `dns` stack."
  type        = string
}

variable "route53_zone_id" {
  description = "Hosted zone ID for the apex domain. Output of the `dns` stack."
  type        = string
}

# ─────────────────── Lambda env vars ───────────────────

variable "public_supabase_url" {
  description = "PUBLIC_SUPABASE_URL for the coach Lambda. Non-secret — passed as a Terraform var, not via sops."
  type        = string
}

variable "public_supabase_anon_key" {
  description = "PUBLIC_SUPABASE_ANON_KEY for the coach Lambda. The publishable key, NOT service-role."
  type        = string
  sensitive   = true
}

variable "secrets_file" {
  description = "Path to the sops-encrypted YAML file with runtime secrets (ANTHROPIC_API_KEY, SENTRY_DSN). Set to null on first apply (before the file exists); the Lambda starts up but the coach endpoint returns 503 until secrets are populated."
  type        = string
  default     = null
}

variable "extra_lambda_env" {
  description = "Optional extra env vars for the Lambda (e.g. COACH_PROVIDER, OPENAI_BASE_URL). Merged into the Lambda's environment.variables block alongside the secrets."
  type        = map(string)
  default     = {}
}

# ─────────────────── Lambda code ───────────────────

variable "lambda_zip_path" {
  description = "Optional path to a pre-built Lambda zip. Default null → the module zips its placeholder directory and uses that. CI replaces the code on every web@* tag via `aws lambda update-function-code`, so this only matters on the very first apply."
  type        = string
  default     = null
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for the coach Lambda — caps the function's worst-case concurrency so a burst can't rack up unbounded Anthropic spend. The lambda_throttles alarm fires when the cap is hit. Default null = no reservation. Recommended: 50 for prod, 5 for preview."
  type        = number
  default     = null
}

# ─────────────────── Tagging ───────────────────

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default     = {}
}
