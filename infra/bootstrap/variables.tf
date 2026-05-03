variable "aws_region" {
  description = "Region for the Terraform state bucket."
  type        = string
  default     = "eu-west-2"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket holding remote tfstate for every other stack. Locking is S3-native (use_lockfile = true) — no DynamoDB table needed since Terraform 1.10."
  type        = string
}
