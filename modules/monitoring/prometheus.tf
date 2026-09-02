# ---------------------------------------------------------------------------
# Monitoring.
#
# One chart, kube-prometheus-stack, brings the whole stack: the Prometheus
# operator, Prometheus itself, Alertmanager, Grafana, node-exporter on every
# node and kube-state-metrics. Installing them separately would mean wiring the
# scrape configuration and the Grafana data source by hand, and the chart
# already does both.
#
# What that gives, in the terms the brief asks about:
#   node-exporter       CPU, memory, disk and network per node
#   kube-state-metrics  deployment replicas, pod restarts, and the HPA numbers,
#                       which is how the autoscaling shows up on a dashboard
#   Grafana             the dashboards, shipped with the chart, no import needed
# ---------------------------------------------------------------------------

resource "random_password" "grafana_admin" {
  count = var.grafana_admin_password == null ? 1 : 0

  length  = 20
  special = false
}

locals {
  grafana_admin_password = var.grafana_admin_password != null ? var.grafana_admin_password : random_password.grafana_admin[0].result
}

resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      purpose                        = "monitoring"
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  name       = var.release_name
  namespace  = kubernetes_namespace.monitoring.metadata[0].name
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_version

  create_namespace = false

  # The stack pulls a lot of images and the operator has to create the
  # Prometheus and Alertmanager StatefulSets before anything is ready, so the
  # first install is slow.
  timeout = var.chart_timeout
  wait    = true

  values = [
    templatefile("${path.module}/values.yaml", {
      storage_class           = var.storage_class
      prometheus_storage_size = var.prometheus_storage_size
      prometheus_retention    = var.prometheus_retention
      grafana_storage_size    = var.grafana_storage_size
      grafana_service_type    = var.grafana_service_type
      grafana_admin_user      = var.grafana_admin_user
      grafana_admin_password  = local.grafana_admin_password
    })
  ]
}
