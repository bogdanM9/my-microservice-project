terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project_name
      ManagedBy = "terraform"
    }
  }
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# Remote state backend (S3 + DynamoDB)
#
# Left commented on the first run. There is a chicken-and-egg problem: the
# bucket that stores the state cannot itself be described by a state that is
# already in the bucket. Create it locally first, then move the state in.
# The exact procedure is in the README, section "Remote backend".
# ---------------------------------------------------------------------------
# module "s3_backend" {
#   source      = "./modules/s3-backend"
#   bucket_name = "tfstate-${data.aws_caller_identity.current.account_id}-${var.region}"
#   table_name  = "${var.project_name}-terraform-locks"
# }

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------
module "vpc" {
  source = "./modules/vpc"

  vpc_name           = var.project_name
  vpc_cidr_block     = "10.0.0.0/16"
  public_subnets     = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  private_subnets    = ["10.0.11.0/24", "10.0.12.0/24", "10.0.13.0/24"]
  availability_zones = ["${var.region}a", "${var.region}b", "${var.region}c"]
  cluster_name       = var.cluster_name
}

# ---------------------------------------------------------------------------
# Container registry
# ---------------------------------------------------------------------------
module "ecr" {
  source = "./modules/ecr"

  repository_name = var.repository_name
  scan_on_push    = true
}

# ---------------------------------------------------------------------------
# Database
#
# One call, two possible shapes. use_aurora = false gives a single RDS instance,
# use_aurora = true gives an Aurora cluster, and nothing else in this file
# changes. The subnets are the private ones, so the database has no route to the
# internet, and the only thing allowed in is the CIDR of the VPC itself.
# ---------------------------------------------------------------------------
module "rds" {
  source = "./modules/rds"

  name       = "${var.project_name}-db"
  use_aurora = var.use_aurora

  engine         = var.db_engine
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class
  multi_az       = var.db_multi_az

  aurora_replica_count = var.aurora_replica_count

  db_name  = var.db_name
  username = var.db_username

  vpc_id = module.vpc.vpc_id

  # Private subnets by default, so the database has no route to the internet.
  # Flipping db_publicly_accessible moves it to the public subnets and gives it
  # a public address, which is occasionally useful while developing and a bad
  # idea otherwise.
  subnet_ids          = var.db_publicly_accessible ? module.vpc.public_subnet_ids : module.vpc.private_subnet_ids
  publicly_accessible = var.db_publicly_accessible

  # Only the VPC itself is allowed in. The application pods sit inside it, so
  # that is all they need.
  allowed_cidr_blocks = var.db_publicly_accessible ? var.db_public_cidr_blocks : [module.vpc.vpc_cidr_block]

  tags = { Component = "database" }
}

# ---------------------------------------------------------------------------
# Kubernetes cluster
# ---------------------------------------------------------------------------
module "eks" {
  source = "./modules/eks"

  cluster_name  = var.cluster_name
  subnet_ids    = module.vpc.public_subnet_ids
  instance_type = var.instance_type
  desired_size  = 2
  min_size      = 2
  max_size      = 3
}

# ---------------------------------------------------------------------------
# Kubernetes and Helm providers, pointed at the cluster we just created
# ---------------------------------------------------------------------------
data "aws_eks_cluster" "eks" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

data "aws_eks_cluster_auth" "eks" {
  name       = module.eks.cluster_name
  depends_on = [module.eks]
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.eks.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.eks.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.eks.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.eks.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.eks.token
  }
}

# ---------------------------------------------------------------------------
# CI: Jenkins
# ---------------------------------------------------------------------------
module "jenkins" {
  source = "./modules/jenkins"

  chart_version     = var.jenkins_chart_version
  cluster_name      = module.eks.cluster_name
  oidc_provider_arn = module.eks.oidc_provider_arn
  oidc_provider_url = module.eks.oidc_provider_url

  github_username = var.github_username
  github_token    = var.github_token
  github_repo_url = var.github_repo_url
  git_branch      = var.git_branch

  ecr_repository_arn = module.ecr.repository_arn
  ecr_registry       = split("/", module.ecr.repository_url)[0]
  aws_region         = var.region

  # No explicit providers map here on purpose. Listing providers would stop the
  # module from inheriting the ones it does not list, and modules/jenkins also
  # needs the random provider.
  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# Monitoring: Prometheus and Grafana
#
# storage_class comes from the Jenkins module rather than from a string, because
# that is where the gp3 class is created. Reading it from there is what tells
# Terraform the class has to exist before Prometheus asks for a volume.
# ---------------------------------------------------------------------------
module "monitoring" {
  source = "./modules/monitoring"

  namespace     = "monitoring"
  chart_version = var.monitoring_chart_version

  storage_class        = module.jenkins.storage_class_name
  grafana_service_type = var.grafana_service_type

  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# Database credentials for the application.
#
# Terraform is the only place that knows both halves: the endpoint and password
# come out of modules/rds, and the application reads them as environment
# variables. Writing them into a Secret here means the Helm chart in charts/
# only has to name the Secret, and nothing sensitive is committed.
# ---------------------------------------------------------------------------
resource "kubernetes_secret" "django_db" {
  metadata {
    name      = var.app_db_secret_name
    namespace = var.app_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "django-app"
    }
  }

  data = {
    POSTGRES_HOST     = module.rds.endpoint
    POSTGRES_PORT     = tostring(module.rds.port)
    POSTGRES_DB       = module.rds.database_name
    POSTGRES_USER     = module.rds.master_username
    POSTGRES_PASSWORD = module.rds.master_password
  }

  type = "Opaque"
}

# ---------------------------------------------------------------------------
# CD: Argo CD
# ---------------------------------------------------------------------------
module "argo_cd" {
  source = "./modules/argo_cd"

  namespace     = "argocd"
  chart_version = var.argocd_chart_version

  github_username = var.github_username
  github_token    = var.github_token
  github_repo_url = var.github_repo_url
  git_branch      = var.git_branch

  chart_path = "charts/django-app"

  depends_on = [module.eks]
}
