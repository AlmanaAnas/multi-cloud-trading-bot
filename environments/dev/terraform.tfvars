# environments/dev/terraform.tfvars

# ── you know these now ──────────────────────────────────
environment  = "dev"
project_name = "trading-bot"
github_org   = "AlmanaAnas"
github_repo  = "multi-cloud-trading-bot"
aws_region   = "us-east-1"
gcp_region   = "us-central1"
trading_pair = "BTC/USDT"

# ── fill in when you create your AWS account ───────────
# (leave as FILL_IN_LATER for now)

# ── fill in when you create your GCP project ──────────
gcp_project_id     = "FILL_IN_LATER"
gcp_project_number = "FILL_IN_LATER"

# ── controls ───────────────────────────────────────────
ingestion_enabled = true