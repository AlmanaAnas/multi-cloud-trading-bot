# modules/aws/lambda/main.tf



# Zips the source code directory — triggers redeployment when any file changes

data "archive_file" "source" {

  type        = "zip"

  source_dir  = var.source_dir

  output_path = "${path.module}/dist/${var.function_name}.zip"

  excludes    = ["__pycache__", "*.pyc", ".pytest_cache", "tests/"]

}



resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  role             = var.iam_role_arn
  handler          = var.handler
  runtime          = var.runtime
  memory_size      = var.memory_mb
  timeout          = var.timeout_seconds
  filename         = data.archive_file.source.output_path
  source_code_hash = data.archive_file.source.output_base64sha256

  # VPC config — Lambda runs in the private subnet
  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = var.security_group_ids
  }

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  tags       = var.tags
  depends_on = [aws_cloudwatch_log_group.this]
}



resource "aws_cloudwatch_log_group" "this" {

  name              = "/aws/lambda/${var.function_name}"

  retention_in_days = var.log_retention_days

  tags              = var.tags

}



# Alarm — fires if Lambda errors exceed 3 in a 5 minute window

resource "aws_cloudwatch_metric_alarm" "errors" {

  alarm_name          = "${var.function_name}-errors"

  comparison_operator = "GreaterThanThreshold"

  evaluation_periods  = 1

  metric_name         = "Errors"

  namespace           = "AWS/Lambda"

  period              = 300

  statistic           = "Sum"

  threshold           = 3

  treat_missing_data  = "notBreaching"



  dimensions = {

    FunctionName = aws_lambda_function.this.function_name

  }



  tags = var.tags

}