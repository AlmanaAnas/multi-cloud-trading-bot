# modules/gcp/vpc/variables.tf

variable "project_id" {
  type = string
}

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "vpc_cidr" {
  type    = string
  default = "10.1.0.0/16"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.1.1.0/24"
}

variable "connector_subnet_cidr" {
  description = "Must be /28 — Serverless VPC Connector requirement"
  type        = string
  default     = "10.1.4.0/28"
}

variable "labels" {
  type    = map(string)
  default = {}
}