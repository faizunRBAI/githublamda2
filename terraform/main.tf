terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.50"
    }
  }

  backend "s3" {}
}

provider "aws" {
  region = var.aws_region
}

# ──────────────────────────────────────────────
# Variables
# ──────────────────────────────────────────────

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "us-east-1"
}

variable "function_name" {
  description = "Name of the Lambda function"
  type        = string
  default     = "githublamda2"
}

variable "s3_bucket" {
  description = "S3 bucket that holds the Lambda zip artifact"
  type        = string
}

variable "s3_key" {
  description = "S3 key of the Lambda zip artifact"
  type        = string
  default     = "lambda/package.zip"
}

variable "app_env" {
  description = "Value for the APP_ENV environment variable"
  type        = string
  default     = "production"
}

variable "lambda_log_retention_days" {
  description = "CloudWatch log retention in days"
  type        = number
  default     = 14
}

# ──────────────────────────────────────────────
# IAM role for Lambda
# ──────────────────────────────────────────────

data "aws_iam_policy_document" "lambda_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
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

# ──────────────────────────────────────────────
# CloudWatch log group
# ──────────────────────────────────────────────

resource "aws_cloudwatch_log_group" "lambda_logs" {
  name              = "/aws/lambda/${var.function_name}"
  retention_in_days = var.lambda_log_retention_days
}

# ──────────────────────────────────────────────
# Lambda function
# ──────────────────────────────────────────────

resource "aws_lambda_function" "app" {
  function_name = var.function_name
  description   = "FastAPI application wrapped with Mangum"

  role    = aws_iam_role.lambda_exec.arn
  runtime = "python3.12"
  handler = "lambda_handler.handler"

  s3_bucket = var.s3_bucket
  s3_key    = var.s3_key

  timeout     = 30
  memory_size = 256

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

# ──────────────────────────────────────────────
# Lambda Function URL  (auth = NONE → public)
# ──────────────────────────────────────────────

resource "aws_lambda_function_url" "app_url" {
  function_name      = aws_lambda_function.app.function_name
  authorization_type = "NONE"

  cors {
    allow_credentials = false
    allow_origins     = ["*"]
    allow_methods     = ["*"]
    allow_headers     = ["*"]
    max_age           = 86400
  }
}

# Resource-based policy that allows unauthenticated invocations through the
# Function URL (required when authorization_type = "NONE").
resource "aws_lambda_permission" "allow_function_url" {
  statement_id           = "AllowFunctionURLPublicAccess"
  action                 = "lambda:InvokeFunctionUrl"
  function_name          = aws_lambda_function.app.function_name
  principal              = "*"
  function_url_auth_type = "NONE"
}

# ──────────────────────────────────────────────
# Outputs
# ──────────────────────────────────────────────

output "function_name" {
  description = "Lambda function name"
  value       = aws_lambda_function.app.function_name
}

output "function_arn" {
  description = "Lambda function ARN"
  value       = aws_lambda_function.app.arn
}

output "function_url" {
  description = "Public Function URL"
  value       = aws_lambda_function_url.app_url.function_url
}