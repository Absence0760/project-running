terraform {
  backend "s3" {
    bucket       = "runonward-tfstate"
    key          = "github-oidc/terraform.tfstate"
    region       = "eu-west-2"
    use_lockfile = true
    encrypt      = true
  }
}
