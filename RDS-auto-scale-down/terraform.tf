terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
  
  # Backend configuration for state management
  # Uncomment and configure for remote state
      backend "s3" {
      bucket = "k-nakatani-terraform-undotuusin-rds-bucket"
      key    = "tfstate/dev/terraform.tfstate"
      region = "ap-northeast-1"
    }
}

provider "aws" {
  region = var.region
  
  default_tags {
    tags = {
    }
  }
}