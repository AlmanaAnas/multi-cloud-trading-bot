# environments/dev/main.tf

# ── AWS ────────────────────────────────────────────────────


module "aws_vpc" {
  source              = "../../modules/aws/vpc"
  project_name        = var.project_name
  environment         = var.environment
  availability_zone   = "${var.aws_region}a"
  tags                = local.common_tags
}

module "gcp_vpc" {
  source       = "../../modules/gcp/vpc"
  project_id   = var.gcp_project_id
  project_name = var.project_name
  environment  = var.environment
  region       = var.gcp_region
  labels       = local.common_labels
}


module "aws_iam_oidc" {
  source      = "../../modules/aws/iam-oidc"
  github_org  = var.github_org
  github_repo = var.github_repo
  environment = var.environment
  tags        = local.common_tags
}

module "aws_lambda" {
  source          = "../../modules/aws/lambda"
  function_name   = "${var.project_name}-ingest-${var.environment}"
  source_dir      = "../../app/lambda/ingest"
  iam_role_arn    = module.aws_iam_oidc.lambda_role_arn
  memory_mb       = 256
  timeout_seconds = 30

  # VPC — Lambda now runs in the private subnet
  subnet_ids         = [module.aws_vpc.private_subnet_id]
  security_group_ids = [module.aws_vpc.lambda_security_group_id]

  environment_variables = {
    GCP_PROJECT_ID = var.gcp_project_id
    PUBSUB_TOPIC   = module.gcp_pubsub.topic_name
    TRADING_PAIR   = var.trading_pair
    ENVIRONMENT    = var.environment
  }

  tags = local.common_tags
}

module "aws_eventbridge" {
  source               = "../../modules/aws/eventbridge"
  rule_name            = "${var.project_name}-trigger-${var.environment}"
  schedule_expression  = "rate(1 minute)"
  target_function_arn  = module.aws_lambda.function_arn
  target_function_name = module.aws_lambda.function_name
  enabled              = var.ingestion_enabled
  tags                 = local.common_tags
}

# ── GCP ────────────────────────────────────────────────────

module "gcp_iam_wif" {
  source         = "../../modules/gcp/iam-wif"
  project_id     = var.gcp_project_id
  project_number = var.gcp_project_number
  github_org     = var.github_org
  github_repo    = var.github_repo
  environment    = var.environment
  labels         = local.common_labels
}

module "gcp_signals_function" {
  source                = "../../modules/gcp/cloud-function"
  project_id            = var.gcp_project_id
  region                = var.gcp_region
  function_name         = "${var.project_name}-signals-${var.environment}"
  source_dir            = "../../app/functions/signals"
  entry_point           = "handler"
  memory_mb             = 256
  timeout_seconds       = 60
  min_instances         = 0
  max_instances         = 3
  service_account_email = module.gcp_iam_wif.cloud_function_sa_email

  # VPC — Cloud Function connects through the VPC connector
  vpc_connector_id = module.gcp_vpc.connector_id
  network_tags     = [module.gcp_vpc.cloud_function_tag]

  environment_variables = {
    GCP_PROJECT_ID = var.gcp_project_id
    BQ_DATASET     = module.gcp_bigquery.dataset_id
    BQ_TABLE       = module.gcp_bigquery.table_id
    ENVIRONMENT    = var.environment
  }

  labels = local.common_labels
}

module "gcp_pubsub" {
  source        = "../../modules/gcp/pubsub"
  project_id    = var.gcp_project_id
  topic_name    = "${var.project_name}-market-data-${var.environment}"
  push_endpoint = module.gcp_signals_function.function_uri
  labels        = local.common_labels
}

module "gcp_bigquery" {
  source     = "../../modules/gcp/bigquery"
  project_id = var.gcp_project_id
  dataset_id = "trading_bot_${var.environment}"
  table_id   = "signals"
  labels     = local.common_labels
}

# ── locals ─────────────────────────────────────────────────

locals {
  common_tags = {
    Environment = var.environment
    Project     = var.project_name
    ManagedBy   = "terraform"
  }

  common_labels = {
    environment = var.environment
    project     = var.project_name
    managed_by  = "terraform"
  }
}

