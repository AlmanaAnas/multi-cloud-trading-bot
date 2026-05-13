# modules/gcp/cloud-function/main.tf

# Zip the source code — triggers redeployment when any file changes
data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/dist/${var.function_name}.zip"
  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests/"]
}

# Upload zipped source to GCS so Cloud Function can read it
resource "google_storage_bucket" "source" {
  name                        = "${var.project_id}-fn-source-${var.function_name}"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  force_destroy               = true

  labels = var.labels
}

resource "google_storage_bucket_object" "source" {
  name   = "${var.function_name}-${data.archive_file.source.output_md5}.zip"
  bucket = google_storage_bucket.source.name
  source = data.archive_file.source.output_path
}

# Cloud Function 2nd gen
resource "google_cloudfunctions2_function" "this" {
  name     = var.function_name
  project  = var.project_id
  location = var.region

  build_config {
    runtime     = var.runtime
    entry_point = var.entry_point

    source {
      storage_source {
        bucket = google_storage_bucket.source.name
        object = google_storage_bucket_object.source.name
      }
    }
  }

service_config {
  min_instance_count               = var.min_instances
  max_instance_count               = var.max_instances
  available_memory                 = "${var.memory_mb}M"
  timeout_seconds                  = var.timeout_seconds
  service_account_email            = var.service_account_email
  environment_variables            = var.environment_variables
  vpc_connector                    = var.vpc_connector_id
  vpc_connector_egress_settings    = "PRIVATE_RANGES_ONLY"
  ingress_settings                 = "ALLOW_INTERNAL_ONLY"
}

  labels = var.labels
}

# Allow Pub/Sub to invoke the function
resource "google_cloud_run_service_iam_member" "pubsub_invoker" {
  project  = var.project_id
  location = var.region
  service  = google_cloudfunctions2_function.this.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:service-${data.google_project.project.number}@gcp-sa-pubsub.iam.gserviceaccount.com"
}

data "google_project" "project" {
  project_id = var.project_id
}