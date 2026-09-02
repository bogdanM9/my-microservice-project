# ---------------------------------------------------------------------------
# Storage class
#
# Jenkins asks for a PersistentVolumeClaim. EKS ships without a default storage
# class, so without this the claim stays Pending and Jenkins never starts.
# ---------------------------------------------------------------------------
resource "kubernetes_storage_class_v1" "ebs" {
  metadata {
    name = "ebs-sc"

    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner = "ebs.csi.aws.com"
  reclaim_policy      = "Delete"

  # WaitForFirstConsumer, not Immediate. The volume must be created in the same
  # availability zone as the node that ends up running the pod. Immediate would
  # sometimes create it in the wrong zone and the pod would never schedule.
  volume_binding_mode = "WaitForFirstConsumer"

  parameters = {
    type = "gp3"
  }
}

resource "kubernetes_namespace" "jenkins" {
  metadata {
    name = var.namespace
  }
}

# ---------------------------------------------------------------------------
# IRSA: the IAM role that the Kaniko pod assumes to push to ECR
#
# No AWS access keys anywhere. The service account below is annotated with this
# role ARN, EKS injects a web identity token into the pod, and the AWS SDK
# inside Kaniko trades that token for temporary credentials.
# ---------------------------------------------------------------------------
locals {
  oidc_host = replace(var.oidc_provider_url, "https://", "")
}

resource "aws_iam_role" "jenkins_ecr" {
  name = "${var.cluster_name}-jenkins-ecr-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_host}:sub" = "system:serviceaccount:${var.namespace}:${var.service_account_name}"
            "${local.oidc_host}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "jenkins_ecr" {
  name = "${var.cluster_name}-jenkins-ecr-policy"
  role = aws_iam_role.jenkins_ecr.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # GetAuthorizationToken is account wide by design, it cannot be scoped
        # to a single repository.
        Sid      = "GetAuthToken"
        Effect   = "Allow"
        Action   = ["ecr:GetAuthorizationToken"]
        Resource = "*"
      },
      {
        # Everything else is limited to our one repository.
        Sid    = "PushPullOurRepositoryOnly"
        Effect = "Allow"
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
        Resource = var.ecr_repository_arn
      }
    ]
  })
}

resource "kubernetes_service_account" "jenkins" {
  metadata {
    name      = var.service_account_name
    namespace = kubernetes_namespace.jenkins.metadata[0].name

    annotations = {
      "eks.amazonaws.com/role-arn" = aws_iam_role.jenkins_ecr.arn
    }
  }
}

# ---------------------------------------------------------------------------
# Kaniko needs to be told to use the ECR credential helper for our registry.
# Mounted into the agent pod at /kaniko/.docker/config.json by the Jenkinsfile.
# ---------------------------------------------------------------------------
resource "kubernetes_config_map" "kaniko_docker_config" {
  metadata {
    name      = var.kaniko_config_map_name
    namespace = kubernetes_namespace.jenkins.metadata[0].name
  }

  data = {
    "config.json" = jsonencode({
      credHelpers = {
        (var.ecr_registry) = "ecr-login"
      }
    })
  }
}

# ---------------------------------------------------------------------------
# Jenkins itself
# ---------------------------------------------------------------------------

# If no password was given in terraform.tfvars, generate one instead of
# shipping a weak default. Jenkins is on a public load balancer, so "admin123"
# is not good enough even for a lab.
resource "random_password" "admin" {
  count = var.admin_password == "" ? 1 : 0

  length  = 20
  special = false
}

locals {
  admin_password = var.admin_password != "" ? var.admin_password : random_password.admin[0].result
}

resource "helm_release" "jenkins" {
  name       = "jenkins"
  namespace  = kubernetes_namespace.jenkins.metadata[0].name
  repository = "https://charts.jenkins.io"
  chart      = "jenkins"
  version    = var.chart_version

  create_namespace = false

  # Jenkins takes a while to boot the first time because it installs plugins.
  timeout = 900
  wait    = true

  values = [
    templatefile("${path.module}/values.yaml", {
      admin_user           = var.admin_user
      admin_password       = local.admin_password
      ecr_registry         = var.ecr_registry
      aws_region           = var.aws_region
      service_account_name = var.service_account_name
      storage_class        = kubernetes_storage_class_v1.ebs.metadata[0].name
      github_username      = var.github_username
      github_token         = var.github_token
      github_repo_url      = var.github_repo_url
      git_branch           = var.git_branch
      job_name             = var.job_name
    })
  ]

  depends_on = [
    kubernetes_service_account.jenkins,
    kubernetes_config_map.kaniko_docker_config,
  ]
}
