output "namespace" {
  description = "Namespace Argo CD runs in"
  value       = var.namespace
}

output "release_name" {
  description = "Name of the Argo CD Helm release"
  value       = helm_release.argo_cd.name
}

output "application_name" {
  description = "Name of the Argo CD Application that watches the chart"
  value       = var.app_name
}

output "server_url_command" {
  description = "Reads the hostname of the Argo CD load balancer"
  value       = "kubectl -n ${var.namespace} get svc ${var.name}-argocd-server -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "admin_password_command" {
  description = "Reads the initial Argo CD admin password"
  value       = "kubectl -n ${var.namespace} get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}
