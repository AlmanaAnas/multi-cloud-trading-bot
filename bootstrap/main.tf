# bootstrap/main.tf
# ─────────────────────────────────────────────────────────
# Run this ONCE manually before anything else.
# It creates the S3 bucket and DynamoDB table that all
# other Terraform in this project uses to store state.
#
# How to run:
#   cd bootstrap
#   terraform init
#   terraform apply
# ─────────────────────────────────────────────────────────

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # intentionally local state — this is the one place that is correct
  # there is no remote backend yet because this file creates it
}

provider "aws" {
  region = var.aws_region
}

# ── S3 bucket for Terraform state ─────────────────────────

resource "aws_s3_bucket" "state" {
  bucket        = var.state_bucket_name
  force_destroy = false

  tags = {
    Name      = "Terraform state"
    ManagedBy = "terraform"
    Project   = var.project_name
  }
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket                  = aws_s3_bucket.state.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# ── DynamoDB table for state locking ──────────────────────

resource "aws_dynamodb_table" "lock" {
  name         = var.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Name      = "Terraform state lock"
    ManagedBy = "terraform"
    Project   = var.project_name
  }
}