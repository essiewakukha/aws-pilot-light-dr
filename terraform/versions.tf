terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.60"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Recommended: remote state in a bucket that is itself replicated to the DR
  # Region, so you can still run Terraform when the primary Region is down.
  # backend "s3" {
  #   bucket         = "my-tfstate-bucket"
  #   key            = "pilot-light-dr/terraform.tfstate"
  #   region         = "us-west-2"
  #   dynamodb_table = "tf-locks"
  #   encrypt        = true
  # }
}

provider "aws" {
  alias  = "primary"
  region = var.primary_region
  default_tags { tags = local.tags }
}

provider "aws" {
  alias  = "dr"
  region = var.dr_region
  default_tags { tags = local.tags }
}