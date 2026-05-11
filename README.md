# Multi-Cloud Trading Bot

Multi-cloud infrastructure project built with Terraform, AWS, and GCP.

## Infrastructure
- AWS Lambda + EventBridge (eu-north-1)
- GCP Pub/Sub + Cloud Functions + BigQuery (europe-west1)
- CI/CD via GitHub Actions with OIDC authentication
- Zero long-lived credentials anywhere