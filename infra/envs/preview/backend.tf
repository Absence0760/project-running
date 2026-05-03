terraform {
  backend "s3" {
    bucket         = "runonward-tfstate"
    key            = "envs/preview/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "runonward-tf-lock"
    encrypt        = true
  }
}
