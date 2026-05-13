# modules/gcp/vpc/main.tf
#
# Creates:
#   - Custom VPC (no auto-created subnets)
#   - Private subnet with Private Google Access enabled
#   - Connector subnet (/28) for Serverless VPC Access
#   - Serverless VPC Access Connector (Cloud Function → VPC)
#   - Firewall rules for Cloud Function
#   - VPC Firewall Policy (hierarchical deny-all default)
#   - Cloud Router + Cloud NAT (only if Cloud Function needs external egress)

resource "google_compute_network" "main" {
  name                    = "${var.project_name}-vpc-${var.environment}"
  project                 = var.project_id
  auto_create_subnetworks = false  # we control every subnet manually
  routing_mode            = "REGIONAL"
}

# ── Private subnet ─────────────────────────────────────────
# Cloud Function connects to this via VPC connector
# Private Google Access = no public IPs needed to reach GCP APIs

resource "google_compute_subnetwork" "private" {
  name                     = "${var.project_name}-private-${var.environment}"
  project                  = var.project_id
  network                  = google_compute_network.main.id
  region                   = var.region
  ip_cidr_range            = var.private_subnet_cidr
  private_ip_google_access = true  # reach BigQuery, Pub/Sub, GCS without public IP

  log_config {
    aggregation_interval = "INTERVAL_5_MIN"
    flow_sampling        = 0.5
    metadata             = "INCLUDE_ALL_METADATA"
  }
}

# ── Connector subnet ────────────────────────────────────────
# Must be /28 — Serverless VPC Connector strict requirement
# Dedicated subnet — do not put anything else here

resource "google_compute_subnetwork" "connector" {
  name                     = "${var.project_name}-connector-${var.environment}"
  project                  = var.project_id
  network                  = google_compute_network.main.id
  region                   = var.region
  ip_cidr_range            = var.connector_subnet_cidr
  private_ip_google_access = true
}

# ── Serverless VPC Access Connector ───────────────────────
# Connects Cloud Function to the VPC
# Cloud Function egresses through this connector
# This is what allows firewall rules to apply to Cloud Function traffic

resource "google_vpc_access_connector" "main" {
  name          = "${var.project_name}-connector-${var.environment}"
  project       = var.project_id
  region        = var.region
  network       = google_compute_network.main.id
  ip_cidr_range = var.connector_subnet_cidr
  min_instances = 2
  max_instances = 3
  machine_type  = "e2-micro"

  timeouts {
    create = "10m"
  }
}

# ── Firewall rules ─────────────────────────────────────────
# GCP uses target tags to scope rules to specific resources
# Cloud Function gets tag: cloud-function-${environment}

locals {
  cf_tag = "cloud-function-${var.environment}"
}

# Allow Pub/Sub to push messages to Cloud Function
# Pub/Sub push uses Google's service IP ranges
resource "google_compute_firewall" "allow_pubsub_push" {
  name        = "${var.project_name}-allow-pubsub-${var.environment}"
  project     = var.project_id
  network     = google_compute_network.main.id
  direction   = "INGRESS"
  priority    = 900
  description = "Allow Pub/Sub push subscription to invoke Cloud Function"

  allow {
    protocol = "tcp"
    ports    = ["443", "8080"]
  }

  # Google's Pub/Sub service account source ranges
  source_ranges = ["35.191.0.0/16", "130.211.0.0/22"]
  target_tags   = [local.cf_tag]
}

# Allow Cloud Function to call GCP APIs via Private Google Access
resource "google_compute_firewall" "allow_gcp_apis_egress" {
  name        = "${var.project_name}-allow-gcp-apis-${var.environment}"
  project     = var.project_id
  network     = google_compute_network.main.id
  direction   = "EGRESS"
  priority    = 900
  description = "Allow Cloud Function to reach GCP APIs (BigQuery, SM, GCS)"

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  # Private Google Access IP ranges for GCP APIs
  destination_ranges = ["199.36.153.8/30", "199.36.153.4/30"]
  target_tags        = [local.cf_tag]
}

# Allow Cloud Function to reach Telegram API (external HTTPS)
resource "google_compute_firewall" "allow_telegram_egress" {
  name        = "${var.project_name}-allow-telegram-${var.environment}"
  project     = var.project_id
  network     = google_compute_network.main.id
  direction   = "EGRESS"
  priority    = 950
  description = "Allow Cloud Function to send Telegram alerts"

  allow {
    protocol = "tcp"
    ports    = ["443"]
  }

  destination_ranges = ["0.0.0.0/0"]
  target_tags        = [local.cf_tag]
}

# Deny all other ingress — explicit deny after specific allows
resource "google_compute_firewall" "deny_all_ingress" {
  name        = "${var.project_name}-deny-all-ingress-${var.environment}"
  project     = var.project_id
  network     = google_compute_network.main.id
  direction   = "INGRESS"
  priority    = 65534
  description = "Default deny all ingress — must be explicit to allow"

  deny {
    protocol = "all"
  }

  source_ranges = ["0.0.0.0/0"]
}

# ── Private DNS for GCP APIs ───────────────────────────────
# Ensures googleapis.com resolves to private IPs
# Required for Private Google Access to work

resource "google_dns_managed_zone" "googleapis" {
  name        = "${var.project_name}-googleapis-${var.environment}"
  project     = var.project_id
  dns_name    = "googleapis.com."
  description = "Private zone for GCP API private access"
  visibility  = "private"

  private_visibility_config {
    networks {
      network_url = google_compute_network.main.id
    }
  }
}


resource "google_dns_record_set" "googleapis_cname" {
  name         = "*.googleapis.com."
  project      = var.project_id
  managed_zone = google_dns_managed_zone.googleapis.name
  type         = "CNAME"
  ttl          = 300
  rrdatas      = ["restricted.googleapis.com."]
}