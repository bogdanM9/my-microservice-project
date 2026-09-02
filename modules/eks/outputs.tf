output "cluster_name" {
  description = "Name of the cluster"
  value       = aws_eks_cluster.this.name
}

output "cluster_arn" {
  description = "ARN of the cluster"
  value       = aws_eks_cluster.this.arn
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = aws_eks_cluster.this.endpoint
}

output "cluster_version" {
  description = "Kubernetes version running on the control plane"
  value       = aws_eks_cluster.this.version
}

output "cluster_certificate_authority_data" {
  description = "Base64 encoded CA certificate of the cluster"
  value       = aws_eks_cluster.this.certificate_authority[0].data
}

output "node_role_arn" {
  description = "IAM role assumed by the worker nodes"
  value       = aws_iam_role.nodes.arn
}

output "node_group_name" {
  description = "Name of the managed node group"
  value       = aws_eks_node_group.general.node_group_name
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider, needed by every IRSA role"
  value       = aws_iam_openid_connect_provider.oidc.arn
}

output "oidc_provider_url" {
  description = "URL of the IAM OIDC provider"
  value       = aws_iam_openid_connect_provider.oidc.url
}
