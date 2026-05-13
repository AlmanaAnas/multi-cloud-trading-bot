# modules/gcp/vpc/outputs.tf

output "network_id" {
  value = google_compute_network.main.id
}

output "network_name" {
  value = google_compute_network.main.name
}

output "private_subnet_id" {
  value = google_compute_subnetwork.private.id
}

output "connector_id" {
  description = "Passed into Cloud Function as vpc_connector"
  value       = google_vpc_access_connector.main.id
}

output "cloud_function_tag" {
  description = "Apply this network tag to Cloud Function for firewall rules to work"
  value       = local.cf_tag
}