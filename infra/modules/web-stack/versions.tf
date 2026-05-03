terraform {
  required_version = ">= 1.13"
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      version               = "~> 6.0"
      configuration_aliases = [aws.us_east_1]
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.6"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.2"
    }
  }
}
