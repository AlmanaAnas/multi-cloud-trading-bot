# modules/gcp/pubsub/variables.tf

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "topic_name" {
  description = "Name of the Pub/Sub topic"
  type        = string
}

variable "push_endpoint" {
  description = "HTTPS endpoint for the push subscription — Cloud Function trigger URL"
  type        = string
}

variable "ack_deadline_seconds" {
  description = "How long a subscriber has to acknowledge a message"
  type        = number
  default     = 60
}

variable "message_retention_seconds" {
  description = "How long unacked messages are kept"
  type        = number
  default     = 86400
}

variable "max_delivery_attempts" {
  description = "How many times to retry before sending to DLQ"
  type        = number
  default     = 5
}

variable "labels" {
  description = "Labels applied to all resources"
  type        = map(string)
  default     = {}
}