output "cluster_name" {
  value = aws_eks_cluster.eks.name
}

output "cluster_endpoint" {
  value = aws_eks_cluster.eks.endpoint
  # consumers (Kubernetes/Helm providers) must wait until admin access + nodes exist
  depends_on = [aws_eks_access_policy_association.admins, aws_eks_node_group.node_group]
}

output "cluster_certificate_authority_data" {
  value = aws_eks_cluster.eks.certificate_authority[0].data
}

output "node_group_name" {
  value = aws_eks_node_group.node_group.node_group_name
}

output "node_group_arn" {
  value = aws_eks_node_group.node_group.arn
}

output "node_group_status" {
  value = aws_eks_node_group.node_group.status
}

output "oidc_provider_arn" {
  description = "For IRSA trust policies"
  value       = aws_iam_openid_connect_provider.eks.arn
}

output "oidc_issuer_url" {
  value = aws_eks_cluster.eks.identity[0].oidc[0].issuer
}
