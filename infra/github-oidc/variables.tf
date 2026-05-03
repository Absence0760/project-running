variable "aws_region" {
  type    = string
  default = "eu-west-2"
}

variable "github_repo" {
  description = "GitHub `<owner>/<repo>` slug allowed to assume the deploy roles."
  type        = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
