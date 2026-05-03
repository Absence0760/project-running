# Bootstrap stack — creates the Terraform state bucket and DynamoDB
# lock table that every other stack uses as its remote backend.
#
# Run ONCE per AWS account, with local state. After `terraform apply`,
# the other stacks (`dns`, `github-oidc`, `envs/*`) configure their
# `backend.tf` to point at the bucket + table created here.
#
# This stack is the only one that uses local state; everyone else uses
# remote state. Do NOT migrate this stack's own state into the bucket
# it creates — that's a chicken-and-egg situation.

provider "aws" {
  region = var.aws_region
}

# ─────────────────── State bucket ───────────────────

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = false
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ─────────────────── Lock table ───────────────────

resource "aws_dynamodb_table" "lock" {
  name         = var.lock_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  point_in_time_recovery {
    enabled = true
  }
}
