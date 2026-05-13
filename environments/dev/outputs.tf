# environments/dev/outputs.tf
# These print to terminal after terraform apply
# Copy the values marked "copy to GitHub secrets" into your repo settings

output "aws_github_actions_role_arn" {
  description = "Copy to GitHub secret: AWS_ROLE_ARN"
  value       = module.aws_iam_oidc.github_actions_role_arn
}

output "gcp_workload_identity_provider" {
  description = "Copy to GitHub secret: GCP_WORKLOAD_IDENTITY_PROVIDER"
  value       = module.gcp_iam_wif.workload_identity_provider
}

output "gcp_terraform_sa_email" {
  description = "Copy to GitHub secret: GCP_SERVICE_ACCOUNT"
  value       = module.gcp_iam_wif.terraform_sa_email
}

output "lambda_function_name" {
  description = "AWS Lambda function name"
  value       = module.aws_lambda.function_name
}

output "pubsub_topic_name" {
  description = "GCP Pub/Sub topic name"
  value       = module.gcp_pubsub.topic_name
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset ID"
  value       = module.gcp_bigquery.dataset_id
}

output "landing_page_url" {
  description = "Public landing page URL"
  value       = module.landing.website_url
}

output "api_url" {
  description = "Landing page API URL — set this as API_BASE_URL in index.html"
  value       = module.landing_api.api_url
}