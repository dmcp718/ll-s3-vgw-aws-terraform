resource "random_id" "this" {
  byte_length = 4
}

resource "aws_ebs_encryption_by_default" "this" {
  enabled = true
}

terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}
