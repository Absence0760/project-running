variable "env" {
  description = "Environment name — used as a suffix on every resource. e.g. 'prod', 'preview'."
  type        = string
  validation {
    condition     = contains(["prod", "preview"], var.env)
    error_message = "env must be 'prod' or 'preview'."
  }
}

variable "domain_name" {
  description = "Public domain for this env's CloudFront distribution. e.g. 'threkir.com' for prod, 'preview.threkir.com' for preview."
  type        = string
}

variable "aliases" {
  description = "Additional CloudFront aliases (e.g. ['www.threkir.com'] for prod). The cert in `acm_certificate_arn` must cover all of these."
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
  description = "Path to the sops-encrypted YAML file with runtime secrets (ANTHROPIC_API_KEY, SENTRY_DSN, SUPABASE_SERVICE_ROLE_KEY). Every key in the file is merged into the coach Lambda env (the share-run Lambda has a separate env and never sees these). SUPABASE_SERVICE_ROLE_KEY lets the coach handler persist assistant messages (migration 20261122_001 / XSS audit H1); without it the coach still streams but assistant turns aren't saved. Set to null on first apply (before the file exists); the Lambda starts up but the coach endpoint returns 503 until ANTHROPIC_API_KEY is populated."
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

variable "share_run_lambda_zip_path" {
  description = "Optional path to a pre-built share-run Lambda zip (apps/web/lambda/share-run/dist/share-run.zip). Default null → the module reuses the placeholder zip. CI replaces the code on every web@* tag, so this only matters on the very first apply. Persona-hunt finding Casual #4 — handles /share/run/* + /og/run/*.png with per-request SSR."
  type        = string
  default     = null
}

variable "share_route_lambda_zip_path" {
  description = "Optional path to a pre-built share-route Lambda zip (apps/web/lambda/share-route/dist/share-route.zip). Default null → the module reuses the placeholder zip. CI replaces the code on every web@* tag, so this only matters on the very first apply. Web SEO parity with share-run — handles /share/route/* + /og/route/*.png with per-request SSR."
  type        = string
  default     = null
}

variable "public_site_url" {
  description = "Canonical public URL of this env (e.g. 'https://threkir.com' for prod, 'https://preview.threkir.com' for preview). Used by the share-run Lambda to build absolute og:url + og:image URLs in the per-run head tags. Defaults are env-specific; per-env stacks should set this explicitly."
  type        = string
  default     = "https://threkir.com"
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for the coach Lambda — caps the function's worst-case concurrency so a burst can't rack up unbounded Anthropic spend. The lambda_throttles alarm fires when the cap is hit. Default 5 = safe-by-default ceiling; raise to ~50 for prod once real traffic is observed. Set explicitly in env stacks rather than relying on the default."
  type        = number
  default     = 5
}

# ─────────────────── WAF ───────────────────

variable "waf_enabled" {
  description = "Whether to attach an AWS WAF v2 web ACL with a per-IP rate limit on /api/coach* to the CloudFront distribution. Default true. Set false on a env where load tests / e2e suites need to hit the coach endpoint hard."
  type        = bool
  default     = true
}

variable "waf_rate_limit" {
  description = "Per-IP rate limit applied to /api/coach* requests across a 5-minute rolling window (the WAF v2 default). 100 is generous against the per-user daily cap of 2/day — a single legitimate user can never approach it from one IP. (Cap value tracked in apps/web/src/lib/coach/types.ts#TIER_LIMITS.free.dailyLimit — pinned to be kept in lockstep with this comment by security_guards.test.ts.)"
  type        = number
  default     = 100
}

variable "kms_decrypt_principal_arn" {
  description = "Optional principal ARN that needs kms:Decrypt on the env's secrets KMS key (e.g. the GitHub OIDC deploy role). Empty string omits — deploys must then decrypt sops files out-of-band."
  type        = string
  default     = ""
}

# ─────────────────── Alarm fan-out ───────────────────

variable "alert_emails" {
  description = "Email addresses subscribed to the per-env SNS alerts topic. Empty list = no SNS subscription is created (the topic still exists; alarms still publish to it; nothing reads). Empty list is wrong for prod — the audit/cost-controls Medium called out that an unsubscribed throttle alarm is functionally identical to no alarm. Per-address opt-in confirmation email lands the first time terraform apply runs."
  type        = list(string)
  default     = []

  validation {
    condition = alltrue([
      for e in var.alert_emails :
      can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))
    ])
    error_message = "alert_emails must be RFC-shaped email addresses. Placeholder rejection (@example.com / you@) lives in the per-env root's stricter validation block."
  }
}

variable "lambda_throttle_alarm_threshold" {
  description = "Number of Lambda throttles across two 5-min windows that fires the alarm. Default 5 is fine for preview's noisy demo traffic; prod should override to 1 so a single throttle pages immediately (the reserved concurrency is the cost ceiling — hitting it should be a loud signal). audit/cost-controls Medium 2026-05-07."
  type        = number
  default     = 5
}

# ─────────────────── Tagging ───────────────────

variable "tags" {
  description = "Common tags applied to every resource."
  type        = map(string)
  default     = {}
}
