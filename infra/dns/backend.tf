# Remote state in the bucket created by `infra/bootstrap`. Replace the
# bucket name + dynamodb_table name if the bootstrap stack used
# different values.
terraform {
  backend "s3" {
    bucket         = "runonward-tfstate"
    key            = "dns/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "runonward-tf-lock"
    encrypt        = true
  }
}
