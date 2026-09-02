variable "namespace" {
  description = "Namespace Jenkins is installed into"
  type        = string
  default     = "jenkins"
}

variable "chart_version" {
  description = "Version of the jenkins Helm chart"
  type        = string
  default     = "5.8.27"
}

variable "cluster_name" {
  description = "EKS cluster name, used as a prefix for the IAM role names"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the cluster IAM OIDC provider, for IRSA"
  type        = string
}

variable "oidc_provider_url" {
  description = "URL of the cluster IAM OIDC provider, for IRSA"
  type        = string
}

variable "service_account_name" {
  description = "Service account used by both the Jenkins controller and the build agents"
  type        = string
  default     = "jenkins-sa"
}

variable "ecr_repository_arn" {
  description = "ARN of the ECR repository the pipeline is allowed to push to"
  type        = string
}

variable "aws_region" {
  description = "AWS region, passed to Jenkins as a global environment variable"
  type        = string
}

variable "ecr_registry" {
  description = "Registry host, in the form <account>.dkr.ecr.<region>.amazonaws.com"
  type        = string
}

variable "admin_user" {
  description = "Jenkins admin username"
  type        = string
  default     = "admin"
}

variable "admin_password" {
  description = "Jenkins admin password. Leave empty and a random one is generated, readable with the command in the outputs"
  type        = string
  default     = ""
  sensitive   = true
}

variable "kaniko_config_map_name" {
  description = "Name of the ConfigMap holding the Kaniko docker config"
  type        = string
  default     = "kaniko-docker-config"
}

variable "github_username" {
  description = "GitHub username"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token with the repo scope"
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "HTTPS URL of the repository, ending in .git"
  type        = string
}

variable "git_branch" {
  description = "Branch the pipeline reads from and pushes to"
  type        = string
  default     = "lesson-8-9"
}

variable "job_name" {
  description = "Name of the pipeline job the seed job creates"
  type        = string
  default     = "django-app-pipeline"
}
