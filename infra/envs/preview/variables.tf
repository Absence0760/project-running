variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "apex_domain" {
  type    = string
  default = "runonward.app"
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
