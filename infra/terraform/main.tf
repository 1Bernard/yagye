terraform {
  required_version = ">= 1.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Uncomment and configure when the S3 state bucket is provisioned:
  # backend "s3" {
  #   bucket         = "yagye-terraform-state"
  #   key            = "core/terraform.tfstate"
  #   region         = "eu-west-1"
  #   dynamodb_table = "yagye-terraform-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Project     = "yagye"
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "yagye-${var.environment}"
  }
}
