# environments/dev/backend.tf
# Using local backend until AWS account is ready
# Replace with S3 backend when you have your AWS account

terraform {
  backend "local" {
    path = "terraform.tfstate"
  }
}