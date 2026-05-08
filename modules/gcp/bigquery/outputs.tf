# modules/gcp/bigquery/outputs.tf

output "dataset_id" {
  description = "BigQuery dataset ID"
  value       = google_bigquery_dataset.this.dataset_id
}

output "dataset_self_link" {
  description = "Self link of the dataset"
  value       = google_bigquery_dataset.this.self_link
}

output "table_id" {
  description = "BigQuery table ID"
  value       = google_bigquery_table.signals.table_id
}

output "table_self_link" {
  description = "Self link of the signals table"
  value       = google_bigquery_table.signals.self_link
}