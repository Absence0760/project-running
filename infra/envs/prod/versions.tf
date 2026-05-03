terraform {
  required_version = ">= 1.13"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    sops = {
      source  = "carlpett/sops"
      version = "~> 1.2"
    }
  }
}
