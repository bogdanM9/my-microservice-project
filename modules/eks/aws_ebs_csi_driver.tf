# ---------------------------------------------------------------------------
# IAM OIDC provider
#
# This is what makes IRSA (IAM Roles for Service Accounts) possible. Once the
# cluster OIDC issuer is registered as an IAM identity provider, a Kubernetes
# service account can assume an IAM role directly, with no access keys stored
# anywhere. Both the EBS CSI driver below and the Jenkins Kaniko pod use it.
# ---------------------------------------------------------------------------

# Read the real thumbprint from the issuer certificate instead of hardcoding
# one. Hardcoded thumbprints go stale when AWS rotates the certificate.
data "tls_certificate" "oidc" {
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "oidc" {
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]

  tags = {
    Name = "${var.cluster_name}-oidc"
  }
}

# ---------------------------------------------------------------------------
# EBS CSI driver
#
# Jenkins asks for a PersistentVolumeClaim to keep its jobs and configuration.
# Without a CSI driver the claim stays Pending and the Jenkins pod never starts.
# ---------------------------------------------------------------------------

resource "aws_iam_role" "ebs_csi" {
  name = "${var.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${local.oidc_host}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
            "${local.oidc_host}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

locals {
  oidc_host = replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")
}

resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

# Let AWS pick the addon version that matches the cluster Kubernetes version,
# instead of pinning a version that goes out of date.
data "aws_eks_addon_version" "ebs_csi" {
  addon_name         = "aws-ebs-csi-driver"
  kubernetes_version = aws_eks_cluster.this.version
  most_recent        = true
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  addon_version            = data.aws_eks_addon_version.ebs_csi.version
  service_account_role_arn = aws_iam_role.ebs_csi.arn

  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  # The addon runs as pods, so there has to be a node to run them on.
  depends_on = [
    aws_eks_node_group.general,
    aws_iam_role_policy_attachment.ebs_csi,
  ]
}
