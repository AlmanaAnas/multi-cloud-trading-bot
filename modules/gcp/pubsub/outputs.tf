# modules/gcp/pubsub/outputs.tf

output "topic_id" {
  description = "Full topic ID"
  value       = google_pubsub_topic.this.id
}

output "topic_name" {
  description = "Topic name — passed into Lambda as environment variable"
  value       = google_pubsub_topic.this.name
}

output "dlq_topic_id" {
  description = "Dead-letter topic ID"
  value       = google_pubsub_topic.dlq.id
}

output "dlq_topic_name" {
  description = "Dead-letter topic name"
  value       = google_pubsub_topic.dlq.name
}

output "subscription_name" {
  description = "Push subscription name"
  value       = google_pubsub_subscription.push.name
}