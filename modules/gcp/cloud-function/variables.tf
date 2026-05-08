# modules/gcp/cloud-function/variables.tf

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region to deploy the function"
  type        = string
  default     = "us-central1"
}

variable "function_name" {
  description = "Name of the Cloud Function"
  type        = string
}

variable "description" {
  description = "Description of what the function does"
  type        = string
  default     = ""
}

variable "runtime" {
  description = "Function runtime identifier"
  type        = string
  default     = "python311"
}

variable "source_dir" {
  description = "Path to the directory containing function source code"
  type        = string
}

variable "entry_point" {
  description = "Name of the function entry point inside the source code"
  type        = string
  default     = "handler"
}

variable "memory_mb" {
  description = "Memory in MB allocated to the function"
  type        = number
  default     = 256
}

variable "timeout_seconds" {
  description = "Function timeout in seconds"
  type        = number
  default     = 60
}

variable "min_instances" {
  description = "Minimum number of instances — keep at 0 to stay in free tier"
  type        = number
  default     = 0
}

variable "max_instances" {
  description = "Maximum number of concurrent instances"
  type        = number
  default     = 3
}

variable "environment_variables" {
  description = "Environment variables to pass to the function"
  type        = map(string)
  default     = {}
}

variable "service_account_email" {
  description = "Service account the function runs as"
  type        = string
}

variable "labels" {
  description = "Labels applied to all resources"
  type        = map(string)
  default     = {}
}