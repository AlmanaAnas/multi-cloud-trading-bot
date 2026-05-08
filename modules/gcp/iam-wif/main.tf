# modules/gcp/iam-wif/main.tf

# ── Workload Identity Federation ───────────────────────────
# Allows GitHub Actions to authenticate to GCP without
# any service account key files stored anywhere

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "github-pool-${var.environment}"
  display_name              = "GitHub Actions pool"
  description               = "Identity pool for GitHub Actions CI/CD"
}

resource "google_iam_workload_identity_pool_provider" "github" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider-${var.environment}"
  display_name                       = "GitHub Actions provider"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.ref"        = "assertion.ref"
  }

  # Only tokens from your specific repo are accepted
  attribute_condition = "assertion.repository == '${var.github_org}/${var.github_repo}'"
}

# ── Terraform deployer service account ────────────────────
# GitHub Actions impersonates this account to run terraform apply

resource "google_service_account" "terraform" {
  project      = var.project_id
  account_id   = "terraform-deployer-${var.environment}"
  display_name = "Terraform GitHub Actions deployer"
}

resource "google_project_iam_member" "terraform_deployer" {
  project = var.project_id
  role    = "roles/editor"
  member  = "serviceAccount:${google_service_account.terraform.email}"
}

resource "google_service_account_iam_member" "github_wif" {
  service_account_id = google_service_account.terraform.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_org}/${var.github_repo}"
}

# ── Lambda runtime service account ────────────────────────
# AWS Lambda impersonates this account to publish to Pub/Sub

resource "google_service_account" "lambda_runtime" {
  project      = var.project_id
  account_id   = "lambda-pubsub-publisher-${var.environment}"
  display_name = "AWS Lambda Pub/Sub publisher"
}

resource "google_project_iam_member" "lambda_pubsub" {
  project = var.project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.lambda_runtime.email}"
}

# ── Cloud Function service account ────────────────────────
# The Cloud Function runs as this account

resource "google_service_account" "cloud_function" {
  project      = var.project_id
  account_id   = "cloud-function-${var.environment}"
  display_name = "Cloud Function runtime account"
}

resource "google_project_iam_member" "function_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataEditor"
  member  = "serviceAccount:${google_service_account.cloud_function.email}"
}

resource "google_project_iam_member" "function_secret" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.cloud_function.email}"
}

# ── Grafana service account ────────────────────────────────
# Grafana uses this account to read Cloud Monitoring metrics

resource "google_service_account" "grafana" {
  project      = var.project_id
  account_id   = "grafana-reader-${var.environment}"
  display_name = "Grafana observability reader"
}

resource "google_project_iam_member" "grafana_monitoring" {
  project = var.project_id
  role    = "roles/monitoring.viewer"
  member  = "serviceAccount:${google_service_account.grafana.email}"
}

resource "google_project_iam_member" "grafana_bigquery" {
  project = var.project_id
  role    = "roles/bigquery.dataViewer"
  member  = "serviceAccount:${google_service_account.grafana.email}"
}

resource "google_project_iam_member" "grafana_bq_jobs" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.grafana.email}"
}

resource "google_project_iam_member" "grafana_logs" {
  project = var.project_id
  role    = "roles/logging.viewer"
  member  = "serviceAccount:${google_service_account.grafana.email}"
}

resource "google_service_account_key" "grafana" {
  service_account_id = google_service_account.grafana.name
}