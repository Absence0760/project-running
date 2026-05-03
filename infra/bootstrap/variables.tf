variable "aws_region" {
  description = "Region for the Terraform state bucket + lock table."
  type        = string
  default     = "eu-west-2"
}

variable "state_bucket_name" {
  description = "Name of the S3 bucket holding remote tfstate for every other stack."
  type        = string
}

variable "lock_table_name" {
  description = "Name of the DynamoDB table holding state locks."
  type        = string
  default     = "runonward-tf-lock"
}
