output "state_bucket" {
  description = "Pass to: terraform init -backend-config=\"bucket=<this>\""
  value       = aws_s3_bucket.tfstate.bucket
}

output "github_actions_role_arn" {
  description = "Save as GitHub secret AWS_ROLE_ARN"
  value       = aws_iam_role.github_actions.arn
}

output "route53_name_servers" {
  description = "Enter these 4 nameservers in GoDaddy -> Domain -> DNS -> Nameservers -> Change -> I'll use my own"
  value       = var.domain_name == "" ? [] : aws_route53_zone.domain[0].name_servers
}

output "next_steps" {
  value = <<-EOT

    1. GitHub -> Settings -> Secrets and variables -> Actions -> New repository secret
         AWS_ROLE_ARN = ${aws_iam_role.github_actions.arn}
    2. Initialise the main stack against the shared state bucket:
         cd ..  &&  terraform init -backend-config="bucket=${aws_s3_bucket.tfstate.bucket}"
    ${var.domain_name == "" ? "3. (no domain configured)" : "3. GoDaddy: replace nameservers with route53_name_servers above, then set domain_name in ../terraform.tfvars"}
  EOT
}
