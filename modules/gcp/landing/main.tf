variable "project_id"  { type = string }
variable "region"      { type = string }
variable "bucket_name" { type = string }
variable "source_file" { type = string }

resource "google_storage_bucket" "landing" {
  name                        = var.bucket_name
  project                     = var.project_id
  location                    = var.region
  force_destroy               = true
  uniform_bucket_level_access = true

  website {
    main_page_suffix = "index.html"
  }
}

resource "google_storage_bucket_iam_member" "public_read" {
  bucket = google_storage_bucket.landing.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

resource "google_storage_bucket_object" "index" {
  name         = "index.html"
  bucket       = google_storage_bucket.landing.name
  source       = var.source_file
  content_type = "text/html"
}

output "website_url" {
  value = "https://storage.googleapis.com/${google_storage_bucket.landing.name}/index.html"
}