# modules/gcp/bigquery/variables.tf

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "dataset_id" {
  description = "BigQuery dataset ID"
  type        = string
}

variable "dataset_description" {
  description = "Description of the dataset"
  type        = string
  default     = "Trading bot signals and market data"
}

variable "location" {
  description = "Dataset location"
  type        = string
  default     = "US"
}

variable "table_id" {
  description = "BigQuery table ID for trading signals"
  type        = string
  default     = "signals"
}

variable "delete_contents_on_destroy" {
  description = "If true, deletes all table data when the dataset is destroyed"
  type        = bool
  default     = true
}

variable "labels" {
  description = "Labels applied to all resources"
  type        = map(string)
  default     = {}
}