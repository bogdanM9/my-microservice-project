output "namespace" {
  description = "Namespace Jenkins runs in"
  value       = kubernetes_namespace.jenkins.metadata[0].name
}

output "release_name" {
  description = "Name of the Helm release"
  value       = helm_release.jenkins.name
}

output "service_account_name" {
  description = "Service account used by the controller and the build agents"
  value       = kubernetes_service_account.jenkins.metadata[0].name
}

output "irsa_role_arn" {
  description = "IAM role the Kaniko pod assumes in order to push to ECR"
  value       = aws_iam_role.jenkins_ecr.arn
}

output "admin_user" {
  description = "Jenkins admin username"
  value       = var.admin_user
}

output "admin_password_command" {
  description = "Reads the Jenkins admin password out of the cluster"
  value       = "kubectl -n ${kubernetes_namespace.jenkins.metadata[0].name} get secret jenkins -o jsonpath='{.data.jenkins-admin-password}' | base64 -d"
}

output "kaniko_config_map_name" {
  description = "ConfigMap the agent pod mounts at /kaniko/.docker"
  value       = kubernetes_config_map.kaniko_docker_config.metadata[0].name
}

output "storage_class_name" {
  description = "Name of the gp3 storage class this module creates and marks default. It is cluster wide, not specific to Jenkins, and other modules take it from here so that Terraform knows the order to build things in"
  value       = kubernetes_storage_class_v1.ebs.metadata[0].name
}
