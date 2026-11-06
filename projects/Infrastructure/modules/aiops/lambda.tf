# =============================================================== Lambda tools
# One zip with all the Python code; each function uses a different handler.
#   aiops-logs-tools     -> CloudWatch Logs Insights           (Logs agent)
#   aiops-metrics-tools  -> Prometheus via the EKS API proxy   (Metrics agent)
#   aiops-deploy-tools   -> Argo CD / Rollouts / pods          (Deployment agent)
#   aiops-incident       -> alarm -> Kira -> email report

data "aws_caller_identity" "current" {}

data "archive_file" "lambda" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/.build/aiops-lambda.zip"
  excludes    = ["__pycache__"]
}

locals {
  account_id = data.aws_caller_identity.current.account_id
  k8s_env = {
    CLUSTER_NAME     = var.cluster_name
    CLUSTER_ENDPOINT = var.cluster_endpoint
    CLUSTER_CA       = var.cluster_ca
  }
  tools = {
    logs = {
      handler = "logs_tools.handler"
      role    = aws_iam_role.lambda["logs"].arn
      env     = { LOG_GROUP = var.log_group_name }
    }
    metrics = {
      handler = "metrics_tools.handler"
      role    = aws_iam_role.lambda["k8s"].arn
      env     = local.k8s_env
    }
    deploy = {
      handler = "deploy_tools.handler"
      role    = aws_iam_role.lambda["k8s"].arn
      env     = local.k8s_env
    }
  }
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

# logs     = read the app log group only
# k8s      = no AWS permissions at all; Kubernetes read access comes from the EKS access entry (k8s.tf)
# incident = invoke Kira + publish the report
resource "aws_iam_role" "lambda" {
  for_each           = toset(["logs", "k8s", "incident"])
  name               = "telugu-pickles-aiops-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.lambda_trust.json
}

resource "aws_iam_role_policy_attachment" "lambda_basic" {
  for_each   = aws_iam_role.lambda
  role       = each.value.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "logs_read" {
  role = aws_iam_role.lambda["logs"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["logs:StartQuery", "logs:FilterLogEvents"], Resource = ["${var.log_group_arn}", "${var.log_group_arn}:*"] },
      { Effect = "Allow", Action = ["logs:GetQueryResults", "logs:StopQuery"], Resource = "*" },
    ]
  })
}

resource "aws_iam_role_policy" "incident" {
  role = aws_iam_role.lambda["incident"].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = "bedrock:InvokeAgent", Resource = aws_bedrockagent_agent_alias.kira.agent_alias_arn },
      { Effect = "Allow", Action = "sns:Publish", Resource = aws_sns_topic.reports.arn },
    ]
  })
}

# ---------------------------------------------------------------- functions
resource "aws_lambda_function" "tools" {
  for_each         = local.tools
  function_name    = "telugu-pickles-aiops-${each.key}-tools"
  description      = "Bedrock ${each.key} agent tools (read-only)"
  role             = each.value.role
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = each.value.handler
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 60
  memory_size      = 256
  environment {
    variables = each.value.env
  }
}

resource "aws_cloudwatch_log_group" "lambda" {
  for_each          = toset(concat([for k in keys(local.tools) : "telugu-pickles-aiops-${k}-tools"], ["telugu-pickles-aiops-incident"]))
  name              = "/aws/lambda/${each.key}"
  retention_in_days = 7
}

# Only these Bedrock agents may call the tools
resource "aws_lambda_permission" "bedrock" {
  for_each       = local.tools
  statement_id   = "AllowBedrockAgent"
  action         = "lambda:InvokeFunction"
  function_name  = aws_lambda_function.tools[each.key].function_name
  principal      = "bedrock.amazonaws.com"
  source_account = local.account_id
  source_arn     = aws_bedrockagent_agent.specialist[each.key].agent_arn
}

resource "aws_lambda_function" "incident" {
  function_name    = "telugu-pickles-aiops-incident"
  description      = "CloudWatch alarm -> Kira root-cause analysis -> SNS report"
  role             = aws_iam_role.lambda["incident"].arn
  runtime          = "python3.12"
  architectures    = ["arm64"]
  handler          = "incident.handler"
  filename         = data.archive_file.lambda.output_path
  source_code_hash = data.archive_file.lambda.output_base64sha256
  timeout          = 300 # multi-agent investigations take 30-120 s
  memory_size      = 256
  environment {
    variables = {
      AGENT_ID         = aws_bedrockagent_agent.kira.agent_id
      AGENT_ALIAS_ID   = aws_bedrockagent_agent_alias.kira.agent_alias_id
      REPORT_TOPIC_ARN = aws_sns_topic.reports.arn
    }
  }
}

# ---------------------------------------------------------------- alarm -> incident -> report
resource "aws_sns_topic_subscription" "alarm_to_incident" {
  topic_arn = var.alarm_topic_arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.incident.arn
}

resource "aws_lambda_permission" "sns" {
  statement_id  = "AllowAlarmTopic"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.incident.function_name
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
