terraform {
  backend "s3" {
    bucket       = "threkir-tfstate"
    key          = "envs/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}
