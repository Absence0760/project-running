# Remote state in the bucket created by `infra/bootstrap`. Locking is
# S3-native via `use_lockfile = true` — supported since Terraform 1.10.
# No DynamoDB table required.
terraform {
  backend "s3" {
    bucket       = "runonward-tfstate"
    key          = "dns/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
    encrypt      = true
  }
}
