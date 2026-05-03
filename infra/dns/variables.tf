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
  description = "All non-apex names the cert needs to cover. Default null → derived from apex_domain as ['www.<apex>', 'preview.<apex>']. Override to extend (e.g. add 'staging.<apex>') or to drop names you don't need."
  type        = list(string)
  default     = null
}

variable "tags" {
  description = "Tags applied to the hosted zone + cert."
  type        = map(string)
  default     = {}
}
