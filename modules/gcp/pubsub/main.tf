# modules/gcp/pubsub/main.tf

# ── Main topic ─────────────────────────────────────────────
# Receives market data published by AWS Lambda

resource "google_pubsub_topic" "this" {
  name    = var.topic_name
  project = var.project_id
  labels  = var.labels
}

# ── Dead-letter topic ──────────────────────────────────────
# Receives messages that failed delivery after max_delivery_attempts

resource "google_pubsub_topic" "dlq" {
  name    = "${var.topic_name}-dlq"
  project = var.project_id
  labels  = var.labels
}

# ── Push subscription ──────────────────────────────────────
# Pushes messages to the Cloud Function trigger URL

resource "google_pubsub_subscription" "push" {
  name    = "${var.topic_name}-push-sub"
  topic   = google_pubsub_topic.this.name
  project = var.project_id

  ack_deadline_seconds       = var.ack_deadline_seconds
  message_retention_duration = "${var.message_retention_seconds}s"

  push_config {
    push_endpoint = var.push_endpoint
  }

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq.id
    max_delivery_attempts = var.max_delivery_attempts
  }

  retry_policy {
    minimum_backoff = "10s"
    maximum_backoff = "600s"
  }
}

# ── DLQ pull subscription ──────────────────────────────────
# Lets you inspect failed messages manually

resource "google_pubsub_subscription" "dlq_pull" {
  name    = "${var.topic_name}-dlq-pull"
  topic   = google_pubsub_topic.dlq.name
  project = var.project_id

  ack_deadline_seconds       = 600
  message_retention_duration = "604800s"
}