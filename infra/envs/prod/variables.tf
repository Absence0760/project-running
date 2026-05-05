variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "apex_domain" {
  description = "Should match the apex configured in `infra/dns`."
  type        = string
  default     = "runonward.app"
}

variable "public_supabase_url" {
  description = "Production Supabase REST URL. Once `api.runonward.app` is wired, switch to that."
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
