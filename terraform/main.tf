###############################################################################
# CACMS — AWS Free Tier Infrastructure
# Provisions: VPC, EC2 t2.micro, RDS db.t3.micro (PostgreSQL 16)
#
# Usage:
#   cd terraform
#   cp terraform.tfvars.example terraform.tfvars   # fill in your values
#   terraform init
#   terraform plan
#   terraform apply
#
# After apply, Terraform outputs the EC2 public IP and RDS endpoint.
# Use those to build your Flutter APK and fill in .env.production.
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.aws_region
}
