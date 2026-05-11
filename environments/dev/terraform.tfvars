# environments/dev/terraform.tfvars

# ── you know these now ──────────────────────────────────
environment  = "dev"
project_name = "trading-bot"
github_org   = "AlmanaAnas"
github_repo  = "multi-cloud-trading-bot"
aws_region   = "eu-north-1"
gcp_region   = "europe-west1"
trading_pair = "BTC/USDT"

# ── GCP ────────────────────────────────────────────────
gcp_project_id     = "trading-bot-dev-496006"
gcp_project_number = "890516997920"

# ── controls ───────────────────────────────────────────
ingestion_enabled = true