# modules/gcp/cloud-function/outputs.tf

output "function_name" {
  description = "Name of the Cloud Function"
  value       = google_cloudfunctions2_function.this.name
}

output "function_uri" {
  description = "HTTPS trigger URL — passed into pubsub module as push_endpoint"
  value       = google_cloudfunctions2_function.this.service_config[0].uri
}

output "service_account_email" {
  description = "Service account the function runs as"
  value       = var.service_account_email
}