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

# --------------------------- Database ---------------------------

output "db_endpoint" {
  description = "Host to connect to. The Aurora writer endpoint, or the instance address"
  value       = module.rds.endpoint
}

output "db_reader_endpoint" {
  description = "Aurora only. Read only endpoint spread across the readers"
  value       = module.rds.reader_endpoint
}

output "db_engine_version" {
  description = "The engine version that was actually created"
  value       = module.rds.engine_version
}

output "db_port" {
  description = "Port the database listens on"
  value       = module.rds.port
}

output "db_name" {
  description = "Name of the database"
  value       = module.rds.database_name
}

output "db_master_username" {
  description = "Master user name"
  value       = module.rds.master_username
}

output "db_master_password" {
  description = "Master password. Read it with terraform output -raw db_master_password"
  value       = module.rds.master_password
  sensitive   = true
}

output "db_security_group_id" {
  description = "Security group in front of the database"
  value       = module.rds.security_group_id
}

output "db_is_aurora" {
  description = "Which branch of the module was built"
  value       = module.rds.is_aurora
}

# --------------------------- Monitoring ---------------------------

output "monitoring_namespace" {
  description = "Namespace the monitoring stack runs in"
  value       = module.monitoring.namespace
}

output "grafana_admin_user" {
  description = "Grafana administrator user name"
  value       = module.monitoring.grafana_admin_user
}

output "grafana_admin_password" {
  description = "Grafana administrator password. Read it with terraform output -raw grafana_admin_password"
  value       = module.monitoring.grafana_admin_password
  sensitive   = true
}

output "grafana_url_command" {
  description = "Prints the Grafana address once the load balancer has one"
  value       = module.monitoring.grafana_url_command
}

output "grafana_port_forward_command" {
  description = "Reaches Grafana without the load balancer"
  value       = module.monitoring.grafana_port_forward_command
}

output "prometheus_port_forward_command" {
  description = "Prometheus has no load balancer on purpose. This reaches its UI"
  value       = module.monitoring.prometheus_port_forward_command
}
