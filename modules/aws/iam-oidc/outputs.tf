# modules/aws/iam-oidc/outputs.tf

output "github_actions_role_arn" {
  description = "Copy this value into your GitHub secret AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "lambda_role_arn" {
  description = "Passed into the lambda module as iam_role_arn"
  value       = aws_iam_role.lambda.arn
}

output "lambda_role_name" {
  description = "Passed into the lambda module as iam_role_name"
  value       = aws_iam_role.lambda.name
}

output "grafana_role_arn" {
  description = "Passed into the grafana module as aws_cloudwatch_role_arn"
  value       = aws_iam_role.grafana.arn
}

output "oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = aws_iam_openid_connect_provider.github.arn
}