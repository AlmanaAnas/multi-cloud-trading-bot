# 1. Dependency Build Step (Executes on the GitHub Actions Cloud Runner)
resource "null_resource" "install_dependencies" {
  provisioner "local-exec" {
    command = <<EOT
      mkdir -p ${path.module}/temp/python
      if [ -f "${var.source_dir}/requirements.txt" ]; then
        pip install -r ${var.source_dir}/requirements.txt -t ${path.module}/temp/python
      fi
    EOT
  }

  # Triggers a rebuild only if your app's requirements change
  triggers = {
    dependencies_hash = fileexists("${var.source_dir}/requirements.txt") ? filesha256("${var.source_dir}/requirements.txt") : "none"
  }
}

# 2. Package the Dependencies into a Layer Zip
data "archive_file" "layer_zip" {
  type        = "zip"
  source_dir  = "${path.module}/temp"
  output_path = "${path.module}/dist/layer.zip"
  depends_on  = [null_resource.install_dependencies]
}

# 3. Create the AWS Lambda Layer
resource "aws_lambda_layer_version" "this" {
  filename            = data.archive_file.layer_zip.output_path
  layer_name          = "${var.function_name}-lib"
  compatible_runtimes = [var.runtime]
  source_code_hash    = data.archive_file.layer_zip.output_base64sha256
}

# 4. Package the Application Code (from app/lambda/ingest)
data "archive_file" "source" {
  type        = "zip"
  source_dir  = var.source_dir
  output_path = "${path.module}/dist/${var.function_name}_code.zip"
  excludes    = ["__pycache__", "*.pyc", "requirements.txt", "tests/"]
}

# 5. The Cloud-Native Lambda Function
resource "aws_lambda_function" "this" {
  function_name    = var.function_name
  role             = var.iam_role_arn
  handler          = var.handler
  runtime          = var.runtime
  memory_size      = var.memory_mb
  timeout          = var.timeout_seconds
  filename         = data.archive_file.source.output_path
  source_code_hash = data.archive_file.source.output_base64sha256
  
  # Links the pre-packaged libraries to the function
  layers = [aws_lambda_layer_version.this.arn]

  dynamic "environment" {
    for_each = length(var.environment_variables) > 0 ? [1] : []
    content {
      variables = var.environment_variables
    }
  }

  tags = var.tags

  depends_on = [aws_cloudwatch_log_group.this]
}

# 6. CloudWatch Logs (Infrastructure Observability)
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

# 7. Cloud-Native Monitoring (Alarms)
resource "aws_cloudwatch_metric_alarm" "errors" {
  alarm_name          = "${var.function_name}-error-alert"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "Errors"
  namespace           = "AWS/Lambda"
  period              = 60
  statistic           = "Sum"
  threshold           = 0 # Immediate alert if even one execution fails
  treat_missing_data  = "notBreaching"

  dimensions = {
    FunctionName = aws_lambda_function.this.function_name
  }

  tags = var.tags
}