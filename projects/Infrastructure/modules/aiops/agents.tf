# =============================================================== Bedrock multi-agent
#
#                       Kira (SUPERVISOR, Sonnet)
#            ┌──────────────────┼──────────────────────┐
#      logs-agent          metrics-agent          deploy-agent        (COLLABORATORS, Haiku)
#   CloudWatch Logs        Prometheus           Argo CD + Rollouts + pods
#
# Kira breaks a question into parts, asks the specialists (in parallel when possible),
# then correlates their answers into one root-cause analysis. Everything is READ-ONLY.

# ---------------------------------------------------------------- IAM role the agents run as
data "aws_iam_policy_document" "agent_trust" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["bedrock.amazonaws.com"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = ["arn:aws:bedrock:${var.region}:${local.account_id}:agent/*"]
    }
  }
}

resource "aws_iam_role" "agent" {
  name               = "telugu-pickles-aiops-agents"
  assume_role_policy = data.aws_iam_policy_document.agent_trust.json
}

resource "aws_iam_role_policy" "agent" {
  role = aws_iam_role.agent.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Cross-region inference profiles (us.*) route to foundation models in several US regions
        Effect = "Allow"
        Action = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:GetInferenceProfile", "bedrock:GetFoundationModel"]
        Resource = [
          "arn:aws:bedrock:${var.region}:${local.account_id}:inference-profile/${var.supervisor_model}",
          "arn:aws:bedrock:${var.region}:${local.account_id}:inference-profile/${var.specialist_model}",
          "arn:aws:bedrock:*::foundation-model/*",
        ]
      },
      {
        # the supervisor calls its collaborators through their aliases
        Effect   = "Allow"
        Action   = ["bedrock:InvokeAgent", "bedrock:GetAgentAlias"]
        Resource = "arn:aws:bedrock:${var.region}:${local.account_id}:agent-alias/*/*"
      },
    ]
  })
}

# ---------------------------------------------------------------- the 3 specialists
locals {
  specialists = {
    logs = {
      description   = "Searches the Telugu Pickles application logs in CloudWatch"
      instruction   = <<-EOT
        You are the LOGS specialist for the Telugu Pickles e-commerce platform (6 Node.js microservices:
        gateway, auth-service, catalog-service, cart-service, order-service, payment-service, plus frontend).
        Every service writes structured JSON logs (level, service, msg, requestId, err) that are shipped to CloudWatch.
        Use error_summary first to see which services and messages dominate, then search_logs to read
        concrete lines (filter by service, level or text). Always report: the time window you looked at,
        counts, the exact top error messages, which pods they came from, and the first/last time seen.
        Quote log messages exactly. Never invent log lines. If nothing is found, say so clearly.
      EOT
      collaboration = "Ask the logs agent for error messages, stack traces, log counts per service and when errors started."
      functions = [
        {
          name        = "error_summary"
          description = "Counts ERROR and WARN log lines grouped by service and message, biggest first."
          parameters = {
            minutes = { type = "integer", description = "How many minutes back to look (default 60)", required = false }
          }
        },
        {
          name        = "search_logs"
          description = "Returns the most recent log lines, newest first, optionally filtered."
          parameters = {
            service = { type = "string", description = "Service name, e.g. catalog-service. Empty = all.", required = false }
            level   = { type = "string", description = "ERROR (default), WARN, INFO or ALL", required = false }
            minutes = { type = "integer", description = "Minutes back to look (default 30)", required = false }
            text    = { type = "string", description = "Only lines whose message contains this text", required = false }
            limit   = { type = "integer", description = "Max lines (default 30, max 100)", required = false }
          }
        },
      ]
    }

    metrics = {
      description   = "Reads Prometheus metrics of the Telugu Pickles services"
      instruction   = <<-EOT
        You are the METRICS specialist for the Telugu Pickles e-commerce platform running on EKS.
        You read Prometheus: request rate, 5xx error percentage and p95 latency per service, per-pod error
        rates, business metrics (orders by status, PAYMENT_FAILED means checkout problems), CPU/memory/restarts,
        and firing alerts. Start with service_health and firing_alerts. When one service looks bad, call
        pod_errors for it: if only some pods fail, those are probably NEW pods of a canary or blue-green release.
        Report numbers with units and the time window. Say what is normal (error_pct_5xx near 0, p95 under 0.5 s)
        versus abnormal. Never invent numbers.
      EOT
      collaboration = "Ask the metrics agent for error rates, latency, traffic, per-pod comparisons, orders/payments, CPU/memory and firing alerts."
      functions = [
        {
          name        = "service_health"
          description = "Requests per second, 5xx error percentage and p95 latency for every service."
          parameters = {
            minutes = { type = "integer", description = "Rate window in minutes (default 5)", required = false }
          }
        },
        {
          name        = "pod_errors"
          description = "Request rate and 5xx percentage for EACH POD of one service (finds a bad canary pod)."
          parameters = {
            service = { type = "string", description = "Service name, e.g. catalog-service", required = true }
            minutes = { type = "integer", description = "Rate window in minutes (default 10)", required = false }
          }
        },
        {
          name        = "business_metrics"
          description = "Orders placed grouped by status and payment method."
          parameters = {
            minutes = { type = "integer", description = "Window in minutes (default 30)", required = false }
          }
        },
        {
          name        = "pod_resources"
          description = "CPU cores, memory MiB and restarts in the last hour for every app pod."
          parameters  = {}
        },
        {
          name        = "firing_alerts"
          description = "Prometheus alerts currently firing or pending."
          parameters  = {}
        },
      ]
    }

    deploy = {
      description   = "Inspects deployments: Argo CD, Argo Rollouts (blue-green/canary) and pod health"
      instruction   = <<-EOT
        You are the DEPLOYMENT specialist for the Telugu Pickles platform. Deployments are GitOps:
        GitHub Actions builds images, a bot commits new tags to Git, Argo CD syncs the cluster.
        frontend releases with BLUE-GREEN (new version waits as preview until someone promotes it).
        catalog-service releases with CANARY (25% -> Prometheus error check -> 50% -> check -> 100%;
        a failed check aborts and rolls back automatically). Other services use rolling updates.
        Use rollout_status and analysis_runs to tell whether a release is in progress, paused, aborted or
        rolled back, and which metric failed with which measured values. Use argocd_status for the Git
        revision and sync/health, pod_status for CrashLoopBackOff/ImagePullBackOff/OOMKilled/restarts, and
        recent_events for Kubernetes warnings. Report timestamps and image tags. You are read-only: you can
        recommend actions (e.g. "Actions -> Release control -> abort") but never claim to have performed them.
      EOT
      collaboration = "Ask the deployment agent about recent releases, blue-green/canary state, failed release checks, Argo CD sync, pod crashes and Kubernetes events."
      functions = [
        {
          name        = "rollout_status"
          description = "State of Argo Rollouts (frontend blue-green, catalog-service canary): phase, step, stable vs new version."
          parameters = {
            name = { type = "string", description = "Rollout name (frontend or catalog-service). Empty = all.", required = false }
          }
        },
        {
          name        = "analysis_runs"
          description = "Recent automatic release checks with measured values and Successful/Failed."
          parameters = {
            rollout = { type = "string", description = "Rollout name to filter on. Empty = all.", required = false }
            limit   = { type = "integer", description = "How many runs (default 5)", required = false }
          }
        },
        {
          name        = "argocd_status"
          description = "Argo CD application sync and health, deployed Git revision, last sync result, unhealthy resources."
          parameters  = {}
        },
        {
          name        = "pod_status"
          description = "Pods with readiness, restarts, waiting reason, last termination reason and image."
          parameters = {
            service = { type = "string", description = "Only pods of this service (label app). Empty = all.", required = false }
          }
        },
        {
          name        = "recent_events"
          description = "Kubernetes events in the app namespace."
          parameters = {
            minutes       = { type = "integer", description = "Minutes back (default 30)", required = false }
            warnings_only = { type = "boolean", description = "Only Warning events (default true)", required = false }
          }
        },
      ]
    }
  }
}

resource "aws_bedrockagent_agent" "specialist" {
  for_each                    = local.specialists
  agent_name                  = "telugu-pickles-${each.key}-agent"
  description                 = each.value.description
  agent_resource_role_arn     = aws_iam_role.agent.arn
  foundation_model            = var.specialist_model
  instruction                 = each.value.instruction
  idle_session_ttl_in_seconds = 600
  prepare_agent               = false # prepared after its action group is attached
}

resource "aws_bedrockagent_agent_action_group" "specialist" {
  for_each                   = local.specialists
  action_group_name          = "${each.key}-tools"
  agent_id                   = aws_bedrockagent_agent.specialist[each.key].agent_id
  agent_version              = "DRAFT"
  skip_resource_in_use_check = true
  prepare_agent              = true

  action_group_executor {
    lambda = aws_lambda_function.tools[each.key].arn
  }

  function_schema {
    member_functions {
      dynamic "functions" {
        for_each = each.value.functions
        content {
          name        = functions.value.name
          description = functions.value.description
          dynamic "parameters" {
            for_each = functions.value.parameters
            content {
              map_block_key = parameters.key
              type          = parameters.value.type
              description   = parameters.value.description
              required      = parameters.value.required
            }
          }
        }
      }
    }
  }
}

resource "aws_bedrockagent_agent_alias" "specialist" {
  for_each         = local.specialists
  agent_alias_name = "live"
  agent_id         = aws_bedrockagent_agent.specialist[each.key].agent_id
  description      = "Used by Kira"
  depends_on       = [aws_bedrockagent_agent_action_group.specialist]
}

# ---------------------------------------------------------------- Kira, the supervisor
resource "aws_bedrockagent_agent" "kira" {
  agent_name                  = "telugu-pickles-kira"
  description                 = "AIOps supervisor: investigates incidents using the logs, metrics and deployment agents"
  agent_resource_role_arn     = aws_iam_role.agent.arn
  foundation_model            = var.supervisor_model
  agent_collaboration         = "SUPERVISOR"
  idle_session_ttl_in_seconds = 900
  prepare_agent               = false # needs its collaborators first
  instruction                 = <<-EOT
    You are Kira, the AIOps site-reliability engineer for "Telugu Pickles", an e-commerce shop for Indian
    pickles running on Amazon EKS (namespace telugu-pickles). Architecture: React frontend (nginx) -> gateway ->
    auth, catalog, cart, order services; order calls payment-service; each service has its own PostgreSQL database.
    Delivery: GitHub Actions -> ECR -> Git commit -> Argo CD. frontend uses BLUE-GREEN releases, catalog-service
    uses CANARY releases with an automatic Prometheus error check (Argo Rollouts).

    You lead three specialist agents. Delegate; do not guess:
      - logs agent: error messages and when they started (CloudWatch Logs)
      - metrics agent: error %, latency, traffic, per-pod comparison, orders/payments, alerts (Prometheus)
      - deployment agent: releases, rollouts, failed release checks, Argo CD, pod crashes, events
    For an incident, consult ALL THREE, then correlate: did errors start right after a release? Are only the
    new pods failing? Was a canary aborted automatically? Is it one service or a dependency (database, payment)?

    Answer in this format:
      **Summary** - one or two sentences a manager understands.
      **Impact** - which service(s), how many errors / which users or checkouts affected, since when.
      **Root cause** - the most likely cause, with confidence (high / medium / low).
      **Evidence** - bullet list of concrete facts from the specialists (numbers, log messages, timestamps, versions).
      **Recommended actions** - numbered, safest first, with exact commands or GitHub Actions steps
        (e.g. "Actions -> Release control -> catalog-service -> abort", "git revert <deploy commit>").
      **Prevention** - one or two improvements.
    You are READ-ONLY: never claim you changed anything. If data is missing, say what is missing.
    For simple questions (e.g. "is everything healthy?") answer briefly without the full template.
  EOT
}

# Collaborators are attached one after another: each attachment re-prepares Kira,
# and Bedrock rejects two prepares of the same agent at the same time.
resource "aws_bedrockagent_agent_collaborator" "logs" {
  agent_id                   = aws_bedrockagent_agent.kira.agent_id
  collaborator_name          = "logs-agent"
  collaboration_instruction  = local.specialists.logs.collaboration
  relay_conversation_history = "TO_COLLABORATOR"
  agent_descriptor {
    alias_arn = aws_bedrockagent_agent_alias.specialist["logs"].agent_alias_arn
  }
}

resource "aws_bedrockagent_agent_collaborator" "metrics" {
  agent_id                   = aws_bedrockagent_agent.kira.agent_id
  collaborator_name          = "metrics-agent"
  collaboration_instruction  = local.specialists.metrics.collaboration
  relay_conversation_history = "TO_COLLABORATOR"
  agent_descriptor {
    alias_arn = aws_bedrockagent_agent_alias.specialist["metrics"].agent_alias_arn
  }
  depends_on = [aws_bedrockagent_agent_collaborator.logs]
}

resource "aws_bedrockagent_agent_collaborator" "deploy" {
  agent_id                   = aws_bedrockagent_agent.kira.agent_id
  collaborator_name          = "deployment-agent"
  collaboration_instruction  = local.specialists.deploy.collaboration
  relay_conversation_history = "TO_COLLABORATOR"
  agent_descriptor {
    alias_arn = aws_bedrockagent_agent_alias.specialist["deploy"].agent_alias_arn
  }
  depends_on = [aws_bedrockagent_agent_collaborator.metrics]
}

# The alias pins a numbered version of Kira. It is replaced when Kira's instruction or model changes,
# so the chat UI and incident Lambda always use the latest prepared version.
resource "aws_bedrockagent_agent_alias" "kira" {
  agent_alias_name = "live"
  agent_id         = aws_bedrockagent_agent.kira.agent_id
  description      = "Chat UI + incident Lambda"
  depends_on       = [aws_bedrockagent_agent_collaborator.deploy]
  lifecycle {
    replace_triggered_by = [aws_bedrockagent_agent.kira]
  }
}
