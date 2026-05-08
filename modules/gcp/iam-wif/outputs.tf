# modules/gcp/iam-wif/outputs.tf

output "workload_identity_provider" {
  description = "Copy this into your GitHub secret GCP_WORKLOAD_IDENTITY_PROVIDER"
  value       = google_iam_workload_identity_pool_provider.github.name
}

output "terraform_sa_email" {
  description = "Copy this into your GitHub secret GCP_SERVICE_ACCOUNT"
  value       = google_service_account.terraform.email
}

output "lambda_runtime_sa_email" {
  description = "Service account email AWS Lambda uses to publish to Pub/Sub"
  value       = google_service_account.lambda_runtime.email
}

output "cloud_function_sa_email" {
  description = "Passed into cloud-function module as service_account_email"
  value       = google_service_account.cloud_function.email
}

output "grafana_sa_email" {
  description = "Passed into grafana module as grafana_sa_email"
  value       = google_service_account.grafana.email
}

output "grafana_sa_key" {
  description = "Private key for Grafana service account — sensitive"
  value       = base64decode(google_service_account_key.grafana.private_key)
  sensitive   = true
}