# modules/gcp/bigquery/main.tf

resource "google_bigquery_dataset" "this" {
  project                    = var.project_id
  dataset_id                 = var.dataset_id
  friendly_name              = var.dataset_id
  description                = var.dataset_description
  location                   = var.location
  delete_contents_on_destroy = var.delete_contents_on_destroy

  labels = var.labels
}

resource "google_bigquery_table" "signals" {
  project             = var.project_id
  dataset_id          = google_bigquery_dataset.this.dataset_id
  table_id            = var.table_id
  deletion_protection = false

  # Partition by day — keeps query costs low and
  # makes it easy to query signals from a specific date
  time_partitioning {
    type  = "DAY"
    field = "timestamp"
  }

  schema = jsonencode([
    {
      name = "timestamp"
      type = "TIMESTAMP"
      mode = "REQUIRED"
      description = "Time the signal was generated"
    },
    {
      name = "trading_pair"
      type = "STRING"
      mode = "REQUIRED"
      description = "e.g. BTC/USDT"
    },
    {
      name = "price"
      type = "FLOAT"
      mode = "REQUIRED"
      description = "Asset price at signal time"
    },
    {
      name = "rsi"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "RSI indicator value"
    },
    {
      name = "atr"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Average True Range value"
    },
    {
      name = "direction"
      type = "STRING"
      mode = "NULLABLE"
      description = "LONG or SHORT"
    },
    {
      name = "confidence"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Model confidence score 0-100"
    },
    {
      name = "stop_loss"
      type = "FLOAT"
      mode = "NULLABLE"
      description = "Calculated stop loss price"
    },
    {
      name = "environment"
      type = "STRING"
      mode = "REQUIRED"
      description = "dev or prod"
    }
  ])

  labels = var.labels
}