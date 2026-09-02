resource "aws_ecr_repository" "this" {
  name = var.repository_name

  # MUTABLE because the pipeline pushes v1.0.1, v1.0.2 and so on, and during
  # debugging it is convenient to be able to overwrite a tag.
  image_tag_mutability = var.image_tag_mutability

  # Lets terraform destroy remove the repository even when images are still in
  # it. Without this, destroy fails and the repository has to be emptied by hand.
  force_delete = var.force_delete

  image_scanning_configuration {
    scan_on_push = var.scan_on_push
  }

  tags = {
    Name = var.repository_name
  }
}

# Only principals inside this AWS account may push or pull.
data "aws_caller_identity" "current" {}

resource "aws_ecr_repository_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowPushPullWithinAccount"
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"
        }
        Action = [
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload",
        ]
      }
    ]
  })
}

# Keep only the 10 most recent images. Every pipeline run pushes a new tag, so
# without this the repository grows forever and so does the storage bill.
resource "aws_ecr_lifecycle_policy" "this" {
  repository = aws_ecr_repository.this.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep only the last 10 images"
        selection = {
          tagStatus   = "any"
          countType   = "imageCountMoreThan"
          countNumber = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
