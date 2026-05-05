terraform {
  backend "s3" {
    bucket       = "runonward-tfstate"
    key          = "envs/preview/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
