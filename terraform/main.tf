terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# ── Variables ────────────────────────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "function_name" {
  description = "Lambda function name"
  type        = string
  default     = "githublamda2"
}

variable "zip_path" {
  description = "Local path to the deployment zip artifact"
  type        = string
  default     = "function.zip"
}

variable "app_env" {
  description = "Application environment"
  type        = string
  default     = "production"
}

# ── IAM Role ─────────────────────────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "lambda_exec" {
  name               = "${var.function_name}-exec-role"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume_role.json
}

resource "aws_iam_role_policy_attachment" "basic_execution" {
  role       = aws_iam_role.lambda_exec.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ── CloudWatch Log Group ──────────────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = 14
}

# ── Lambda Function ───────────────────────────────────────────────────────────

resource "aws_lambda_function" "app" {
  function_name = var.function_name
  description   = "FastAPI application wrapped with Mangum"

  # Artifact
  filename         = var.zip_path
  source_code_hash = filebase64sha256(var.zip_path)

  # Runtime & handler – MUST match lambda_handler.py::handler = Mangum(app)
  runtime = "python3.11"
  handler = "lambda_handler.handler"

  role = aws_iam_role.lambda_exec.arn

  # Sizing
  memory_size = 256
  timeout     = 30

  environment {
    variables = {
      APP_ENV = var.app_env
    }
  }

  depends_on = [
    aws_iam_role_policy_attachment.basic_execution,
    aws_cloudwatch_log_group.lambda_logs,
  ]
}

# ── Function URL (sole HTTP entry point – no API Gateway) ─────────────────────

resource "aws_lambda_function_url" "app_url" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS", "HEAD"]
    allow_headers     = ["content-type", "authorization", "x-requested-with", "x-amz-date", "x-api-key"]
    expose_headers    = ["content-type", "x-custom-header"]
    max_age           = 86400
  }
}

# ── Outputs ───────────────────────────────────────────────────────────────────

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.app.function_name
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.app.arn
}

output "function_url" {
  description = "Lambda Function URL (public HTTPS endpoint)"
  value       = aws_lambda_function_url.app_url.function_url
}