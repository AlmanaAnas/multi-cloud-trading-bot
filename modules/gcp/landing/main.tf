# modules/gcp/landing/main.tf
# Hosts index.html as a public static website on GCS

variable "project_id" { type = string }
variable "region"     { type = string }
variable "source_file"{ type = string }
variable "bucket_name"{ type = string }

resource "google_storage_bucket" "landing" {
  name          = var.bucket_name
  project       = var.project_id
  location      = var.region
  force_destroy = true

  website {
    main_page_suffix = "index.html"
  }

  uniform_bucket_level_access = true
}

# Make the bucket public so anyone can visit the URL
resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.landing.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# Upload the HTML file
resource "google_storage_bucket_object" "index" {
  name         = "index.html"
  bucket       = google_storage_bucket.landing.name
  source       = var.source_file
  content_type = "text/html"
}

output "website_url" {
  description = "Public URL of the landing page"
  value       = "https://storage.googleapis.com/${google_storage_bucket.landing.name}/index.html"
}