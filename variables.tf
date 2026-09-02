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
  description = <<-EOT
    EC2 instance type for the EKS worker nodes.

    This account is on the AWS Free Plan, which refuses to launch any instance
    type that is not free tier eligible. t3.medium fails with
    "InvalidParameterCombination - The specified instance type is not eligible
    for Free Tier".

    Eligible types in this account, from
    `aws ec2 describe-instance-types --filters Name=free-tier-eligible,Values=true`:
    t3.micro, t3.small, t4g.micro, t4g.small, c7i-flex.large, m7i-flex.large.

    The micro types are unusable here: 1 GiB of RAM is less than Jenkins alone
    requests, and the VPC CNI allows only 4 pods per node on them, against the
    roughly 15 this project needs. m7i-flex.large gives 8 GiB and about 29 pods
    per node.
  EOT
  type        = string
  default     = "m7i-flex.large"
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
  description = <<-EOT
    Version of the jenkins Helm chart.
    The chart version decides the Jenkins core version, and the core has to be
    at least as new as the plugins the controller downloads at startup.
    5.8.27 ships core 2.492.2 and the install failed there, because the current
    plugins already require 2.504.3. 5.9.55 ships core 2.568.2, which is new
    enough for all of them.
  EOT
  type        = string
  default     = "5.9.55"
}

variable "argocd_chart_version" {
  description = "Version of the argo-cd Helm chart. Bump it if Helm reports the version is gone"
  type        = string
  default     = "5.51.6"
}

# ---------------------------------------------------------------------------
# Database
#
# These are the only variables that have to change to swap the whole database
# from a standard RDS instance to an Aurora cluster, or from PostgreSQL to
# MySQL. Everything else the rds module needs it works out on its own.
# ---------------------------------------------------------------------------
variable "use_aurora" {
  description = "false builds a single RDS instance, true builds an Aurora cluster. Aurora is not free tier eligible, so leave it false unless you mean it"
  type        = bool
  default     = false
}

variable "db_engine" {
  description = "postgres or mysql for a standard instance, aurora-postgresql or aurora-mysql for a cluster"
  type        = string
  default     = "postgres"
}

variable "db_engine_version" {
  description = "Engine version. Change it together with db_engine, the parameter group family is derived from both"
  type        = string
  default     = "16.6"
}

variable "db_instance_class" {
  description = "db.t3.micro is free tier eligible for a standard instance. Aurora refuses anything smaller than db.t3.medium"
  type        = string
  default     = "db.t3.micro"
}

variable "db_multi_az" {
  description = "Standard instance only: keep a standby in a second availability zone. Doubles the cost"
  type        = bool
  default     = false
}

variable "aurora_replica_count" {
  description = "Read replicas on top of the Aurora writer. Ignored when use_aurora is false"
  type        = number
  default     = 0
}

variable "db_name" {
  description = "Name of the database created inside the instance or cluster"
  type        = string
  default     = "appdb"
}

variable "db_username" {
  description = "Master user name. The engines reserve admin and root, so do not use those"
  type        = string
  default     = "dbadmin"
}
