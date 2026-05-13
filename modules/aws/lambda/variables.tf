# modules/aws/lambda/variables.tf

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
}

variable "source_dir" {
  description = "Path to the directory containing Lambda source code"
  type        = string
}

variable "handler" {
  description = "Function handler in format file.function"
  type        = string
  default     = "main.handler"
}

variable "runtime" {
  description = "Lambda runtime identifier"
  type        = string
  default     = "python3.11"
}

variable "memory_mb" {
  description = "Memory in MB allocated to the function"
  type        = number
  default     = 256
}

variable "timeout_seconds" {
  description = "Function timeout in seconds"
  type        = number
  default     = 30
}

variable "iam_role_arn" {
  description = "Execution role ARN — output from iam-oidc module"
  type        = string
}

variable "environment_variables" {
  description = "Environment variables to pass to the function"
  type        = map(string)
  default     = {}
}

variable "log_retention_days" {
  description = "How many days to keep Lambda logs in CloudWatch"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "subnet_ids" {
  description = "Private subnet IDs for VPC config — from vpc module output"
  type        = list(string)
  default     = []
}

variable "security_group_ids" {
  description = "Security group IDs — from vpc module output"
  type        = list(string)
  default     = []
}