# modules/aws/vpc/outputs.tf

output "vpc_id" {
  value = aws_vpc.main.id
}

output "public_subnet_id" {
  value = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "Lambda lives in this subnet"
  value       = aws_subnet.private.id
}

output "lambda_security_group_id" {
  description = "Attach this to the Lambda function"
  value       = aws_security_group.lambda.id
}