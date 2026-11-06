# =============================================================== Kira: multi-agent AIOps on the Bedrock Converse API
#
#   Lambda telugu-pickles-kira  (code: projects/aiops-assistant/lambda/kira.py)
#     Kira (supervisor model) --tools--> logs / metrics / deployment agents (specialist model)
#                                          --tools--> CloudWatch Logs, Prometheus, Kubernetes API (read-only)
#   Entry points:  Streamlit chat (lambda:InvokeFunction)   and   CloudWatch alarm -> SNS -> this Lambda
#
# Why not "Bedrock Agents"? Classic Bedrock Agents is in maintenance mode and closed to new accounts.
# The Converse API loop does the same job, is fully visible in kira.py, and needs nothing but this Lambda.

data "aws_caller_identity" "current" {}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/.build/aiops-lambda.zip"
  excludes    = ["__pycache__"]
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  function   = "telugu-pickles-kira"
}

# ---------------------------------------------------------------- IAM
data "aws_iam_policy_document" "lambda_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "kira" {
  name               = "telugu-pickles-aiops-kira"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "kira_basic" {
  role       = aws_iam_role.kira.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# Read the app logs, call the two models, publish reports. Kubernetes access: see k8s.tf.
resource "aws_iam_role_policy" "kira" {
  role = aws_iam_role.kira.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "QueryAppLogs"
        Effect   = "Allow"
        Action   = ["logs:StartQuery", "logs:FilterLogEvents"]
        Resource = [var.log_group_arn, "${var.log_group_arn}:*"]
      },
      {
        Sid      = "ReadQueryResults"
        Effect   = "Allow"
        Action   = ["logs:GetQueryResults", "logs:StopQuery"]
        Resource = "*"
      },
      {
        # us.* inference profiles route to the foundation model in several US regions
        Sid    = "InvokeModels"
        Effect = "Allow"
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
        Resource = [
          "arn:aws:bedrock:${var.region}:${local.account_id}:inference-profile/${var.supervisor_model}",
          "arn:aws:bedrock:${var.region}:${local.account_id}:inference-profile/${var.specialist_model}",
          "arn:aws:bedrock:*::foundation-model/*",
        ]
      },
      {
        Sid      = "PublishReports"
        Effect   = "Allow"
        Action   = "sns:Publish"
        Resource = aws_sns_topic.reports.arn
      },
    ]
  })
}

# ---------------------------------------------------------------- the function
resource "aws_cloudwatch_log_group" "kira" {
  name              = "/aws/lambda/${local.function}"
  retention_in_days = 7
}

resource "aws_lambda_function" "kira" {
  function_name    = local.function
  description      = "Kira AIOps multi-agent (Bedrock Converse): chat + automatic incident reports"
  role             = aws_iam_role.kira.arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "kira.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 300 # an investigation with 3 specialists takes ~15-90 s
  memory_size      = 512

  environment {
    variables = {
      SUPERVISOR_MODEL = var.supervisor_model
      SPECIALIST_MODEL = var.specialist_model
      LOG_GROUP        = var.log_group_name
      CLUSTER_NAME     = var.cluster_name
      CLUSTER_ENDPOINT = var.cluster_endpoint
      CLUSTER_CA       = var.cluster_ca
      REPORT_TOPIC_ARN = aws_sns_topic.reports.arn
    }
  }

  depends_on = [aws_cloudwatch_log_group.kira, aws_iam_role_policy_attachment.kira_basic]
}

# ---------------------------------------------------------------- alarm -> Kira -> report
resource "aws_sns_topic_subscription" "alarm_to_kira" {
  topic_arn = var.alarm_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.kira.arn
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowAlarmTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.kira.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = var.alarm_topic_arn
}

resource "aws_sns_topic" "reports" {
  name = "telugu-pickles-aiops-reports"
}

resource "aws_sns_topic_subscription" "email" {
  count     = var.alert_email == "" ? 0 : 1
  topic_arn = aws_sns_topic.reports.arn
  protocol  = "email"
  endpoint  = var.alert_email
}
