terraform {
  backend "s3" {
    bucket         = "tf-state-trading-bot-almanaanas"
    key            = "dev/terraform.tfstate"
    region         = "us-east-1"
    dynamodb_table = "tf-state-lock"
    encrypt        = true
  }
}