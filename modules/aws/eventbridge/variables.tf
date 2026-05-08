# modules/aws/eventbridge/variables.tf

variable "rule_name" {
  description = "Name of the EventBridge rule"
  type        = string
}

variable "description" {
  description = "Description of the rule"
  type        = string
  default     = "Scheduled trigger for Lambda ingestion"
}

variable "schedule_expression" {
  description = "EventBridge schedule — e.g. rate(1 minute) or cron(0 * * * ? *)"
  type        = string
  default     = "rate(1 minute)"
}

variable "target_function_arn" {
  description = "Lambda function ARN — output from lambda module"
  type        = string
}

variable "target_function_name" {
  description = "Lambda function name — output from lambda module"
  type        = string
}

variable "enabled" {
  description = "Set to false to pause the schedule without destroying anything — useful for demo"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}