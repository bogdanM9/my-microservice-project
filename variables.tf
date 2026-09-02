variable "region" {
  description = "AWS region where everything is created"
  type        = string
  default     = "eu-central-1"
}

variable "project_name" {
  description = "Short prefix used in the name of every resource"
  type        = string
  default     = "lesson-8-9"
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "lesson-8-9-eks"
}

variable "instance_type" {
  description = "EC2 instance type for the EKS worker nodes"
  type        = string
  default     = "t3.medium"
}

variable "repository_name" {
  description = "Name of the ECR repository that holds the Django image"
  type        = string
  default     = "django-app"
}

variable "github_username" {
  description = "GitHub username, used by Jenkins to push and by Argo CD to read"
  type        = string
  sensitive   = true
}

variable "github_token" {
  description = "GitHub Personal Access Token with the repo scope"
  type        = string
  sensitive   = true
}

variable "github_repo_url" {
  description = "HTTPS URL of the GitHub repository, ending in .git"
  type        = string
}

variable "git_branch" {
  description = "Branch that Jenkins reads from and Argo CD watches"
  type        = string
  default     = "lesson-8-9"
}

variable "jenkins_chart_version" {
  description = "Version of the jenkins Helm chart. Bump it if Helm reports the version is gone"
  type        = string
  default     = "5.8.27"
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart. Bump it if Helm reports the version is gone"
  type        = string
  default     = "5.51.6"
}
