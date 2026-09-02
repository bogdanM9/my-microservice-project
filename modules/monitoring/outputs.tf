output "namespace" {
  description = "Namespace the stack runs in."
  value       = kubernetes_namespace.monitoring.metadata[0].name
}

output "release_name" {
  description = "Helm release name, which is the prefix on every object the chart created."
  value       = helm_release.kube_prometheus_stack.name
}

output "chart_version" {
  description = "Chart version that was installed."
  value       = helm_release.kube_prometheus_stack.version
}

output "grafana_admin_user" {
  description = "Grafana administrator user name."
  value       = var.grafana_admin_user
}

output "grafana_admin_password" {
  description = "Grafana administrator password. Read it with terraform output -raw."
  value       = local.grafana_admin_password
  sensitive   = true
}

output "grafana_service_name" {
  description = "Name of the Grafana service, for kubectl."
  value       = "${var.release_name}-grafana"
}

output "grafana_url_command" {
  description = "Prints the Grafana address once the load balancer has one."
  value       = "kubectl -n ${var.namespace} get svc ${var.release_name}-grafana -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'"
}

output "prometheus_port_forward_command" {
  description = "Prometheus has no load balancer on purpose. This reaches its UI without exposing it."
  value       = "kubectl -n ${var.namespace} port-forward svc/${var.release_name}-prometheus 9090:9090"
}

output "grafana_port_forward_command" {
  description = "Reaches Grafana without going through the load balancer, which is what the brief asks for."
  value       = "kubectl -n ${var.namespace} port-forward svc/${var.release_name}-grafana 3000:80"
}
