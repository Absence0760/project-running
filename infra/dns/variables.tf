variable "aws_region" {
  description = "Primary region (everything except the cert)."
  type        = string
  default     = "eu-west-2"
}

variable "apex_domain" {
  description = "The apex domain we own. e.g. 'runonward.app'."
  type        = string
}

variable "subject_alternative_names" {
  description = "All non-apex names the prod cert needs to cover. Put preview here too — one cert across both envs is simpler than two certs."
  type        = list(string)
  default     = ["www.runonward.app", "preview.runonward.app"]
}

variable "tags" {
  description = "Tags applied to the hosted zone + cert."
  type        = map(string)
  default     = {}
}
