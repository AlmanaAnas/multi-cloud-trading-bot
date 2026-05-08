# modules/aws/eventbridge/outputs.tf

output "rule_arn" {
  description = "ARN of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.schedule.arn
}

output "rule_name" {
  description = "Name of the EventBridge rule"
  value       = aws_cloudwatch_event_rule.schedule.name
}

output "rule_state" {
  description = "ENABLED or DISABLED"
  value       = aws_cloudwatch_event_rule.schedule.state
}