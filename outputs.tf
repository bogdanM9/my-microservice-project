# --------------------------- Network ---------------------------

output "vpc_id" {
  description = "ID of the VPC"
  value       = module.vpc.vpc_id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets, where the nodes and load balancers live"
  value       = module.vpc.public_subnet_ids
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = module.vpc.private_subnet_ids
}

# --------------------------- ECR ---------------------------

output "ecr_repository_url" {
  description = "Push target for the pipeline. Paste this into charts/django-app/values.yaml"
  value       = module.ecr.repository_url
}

output "ecr_registry" {
  description = "Registry host only, without the repository name. Used as ECR_REGISTRY in the Jenkinsfile"
  value       = split("/", module.ecr.repository_url)[0]
}

# --------------------------- EKS ---------------------------

output "eks_cluster_name" {
  description = "Cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = module.eks.cluster_endpoint
}

output "kubeconfig_command" {
  description = "Run this to point kubectl at the cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}

output "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider used for IRSA"
  value       = module.eks.oidc_provider_arn
}

# --------------------------- Jenkins ---------------------------

output "jenkins_namespace" {
  description = "Namespace Jenkins runs in"
  value       = module.jenkins.namespace
}

output "jenkins_url_command" {
  description = "Run this to get the Jenkins load balancer hostname"
  value       = "kubectl -n ${module.jenkins.namespace} get svc jenkins -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "jenkins_admin_user" {
  description = "Jenkins admin username"
  value       = module.jenkins.admin_user
}

output "jenkins_password_command" {
  description = "Run this to read the Jenkins admin password out of the cluster"
  value       = module.jenkins.admin_password_command
}

output "jenkins_irsa_role_arn" {
  description = "IAM role assumed by the Kaniko pod so it can push to ECR"
  value       = module.jenkins.irsa_role_arn
}

# --------------------------- Argo CD ---------------------------

output "argocd_namespace" {
  description = "Namespace Argo CD runs in"
  value       = module.argo_cd.namespace
}

output "argocd_url_command" {
  description = "Run this to get the Argo CD load balancer hostname"
  value       = module.argo_cd.server_url_command
}

output "argocd_password_command" {
  description = "Run this to read the initial Argo CD admin password"
  value       = module.argo_cd.admin_password_command
}
