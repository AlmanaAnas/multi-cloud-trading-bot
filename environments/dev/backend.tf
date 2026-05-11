terraform {
  backend "s3" {
    bucket       = "tf-state-trading-bot-almanaanas"
    key          = "dev/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}