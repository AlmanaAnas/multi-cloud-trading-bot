# modules/aws/vpc/variables.tf

variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  type    = string
  default = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "Single AZ — Lambda does not need multi-AZ"
  type        = string
  default     = "eu-north-1a"
}

variable "tags" {
  type    = map(string)
  default = {}
}