variable "aws_region" {
  description = "Primary region (everything except the cert)."
  type        = string
  default     = "us-east-1"
}

variable "apex_domain" {
  description = "The apex domain we own. e.g. 'threkir.com'."
  type        = string
}

variable "subject_alternative_names" {
  description = "All non-apex names the cert needs to cover. Default null → derived from apex_domain as ['www.<apex>', 'preview.<apex>']. Override to extend (e.g. add 'staging.<apex>') or to drop names you don't need."
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Tags applied to the hosted zone + cert."
  type        = map(string)
  default     = {}
}

variable "email_auth_records" {
  description = "Outbound-email sender-authentication records (DKIM / SPF / MX / DMARC), pasted from the sending provider (Resend). Keyed by a short label; `name` is relative to the apex ('' = the apex itself). These are public DNS data — safe to commit in terraform.tfvars."
  type = map(object({
    name    = string
    type    = string
    ttl     = optional(number, 300)
    records = list(string)
  }))
  default = {}
}
