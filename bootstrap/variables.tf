# bootstrap/variables.tf

variable "aws_region" {
  description = "AWS region to create the state bucket in"
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Project name used for tagging"
  type        = string
  default     = "multi-cloud-trading-bot"
}

variable "state_bucket_name" {
  description = "S3 bucket name — must be globally unique across all AWS accounts"
  type        = string
  default     = "FILL_IN_LATER"
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for state locking"
  type        = string
  default     = "tf-state-lock"
}