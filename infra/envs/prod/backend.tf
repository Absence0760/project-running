terraform {
  backend "s3" {
    bucket       = "runonward-tfstate"
    key          = "envs/prod/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
    encrypt      = true
  }
}
