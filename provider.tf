provider "aws" {
  region = "us-east-1"
}

terraform {
  backend "s3" {
    bucket = "my-tf-state-bucket-moe"
    key    = "serverless-webapp-project/terraform.tfstate"
    region = "us-east-1"
  }

  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}
