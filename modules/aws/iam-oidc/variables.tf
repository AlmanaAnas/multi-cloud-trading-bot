# modules/aws/iam-oidc/variables.tf

variable "github_org" {
  description = "GitHub organisation or username"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository name"
  type        = string
}

variable "environment" {
  description = "Deployment environment — dev or prod"
  type        = string
}

variable "grafana_external_id" {
  description = "External ID from Grafana CloudWatch data source setup page — leave as empty string for now"
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}