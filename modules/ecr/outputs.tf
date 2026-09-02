output "repository_url" {
  description = "Full repository URL, in the form <account>.dkr.ecr.<region>.amazonaws.com/<name>"
  value       = aws_ecr_repository.this.repository_url
}

output "repository_arn" {
  description = "ARN of the repository"
  value       = aws_ecr_repository.this.arn
}

output "repository_name" {
  description = "Name of the repository"
  value       = aws_ecr_repository.this.name
}

output "registry_id" {
  description = "AWS account id that owns the registry"
  value       = aws_ecr_repository.this.registry_id
}
