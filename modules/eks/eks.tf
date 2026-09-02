# IAM role that the EKS control plane assumes.
resource "aws_iam_role" "cluster" {
  name = "${var.cluster_name}-cluster-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = "sts:AssumeRole"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_eks_cluster" "this" {
  name     = var.cluster_name
  role_arn = aws_iam_role.cluster.arn
  version  = var.kubernetes_version

  vpc_config {
    subnet_ids = var.subnet_ids

    # Public access is on so that kubectl, Terraform and the Helm provider can
    # reach the API server from outside the VPC. Private access is on as well
    # so that traffic from the nodes stays inside the VPC.
    endpoint_public_access  = true
    endpoint_private_access = true
  }

  access_config {
    # API mode replaces the old aws-auth ConfigMap. Access is granted through
    # EKS access entries instead of by editing a ConfigMap by hand.
    authentication_mode = "API"

    # Gives the IAM identity that ran terraform apply cluster-admin, so kubectl
    # works right away without any extra step.
    bootstrap_cluster_creator_admin_permissions = true
  }

  depends_on = [aws_iam_role_policy_attachment.cluster_policy]

  tags = {
    Name = var.cluster_name
  }
}
