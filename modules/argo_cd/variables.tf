variable "name" {
  description = "Name of the Argo CD Helm release"
  type        = string
  default     = "argo-cd"
}

variable "namespace" {
  description = "Namespace Argo CD is installed into"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "Version of the argo-cd Helm chart"
  type        = string
  default     = "5.51.6"
}

variable "app_name" {
  description = "Name of the Argo CD Application"
  type        = string
  default     = "django-app"
}

variable "destination_namespace" {
  description = "Kubernetes namespace the application is deployed into"
  type        = string
  default     = "default"
}

variable "chart_path" {
  description = "Path inside the repository where the application Helm chart lives"
  type        = string
  default     = "charts/django-app"
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
  description = "Branch Argo CD tracks"
  type        = string
  default     = "lesson-8-9"
}
