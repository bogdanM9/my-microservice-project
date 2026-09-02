variable "namespace" {
  description = "Namespace the whole monitoring stack is installed into. The brief checks it with kubectl get all -n monitoring, so the default matches that."
  type        = string
  default     = "monitoring"
}

variable "chart_version" {
  description = "Version of the kube-prometheus-stack Helm chart. It carries Prometheus, Alertmanager, Grafana, node-exporter and kube-state-metrics, together with the operator that wires them up."
  type        = string
  default     = "88.6.2"
}

variable "release_name" {
  description = "Helm release name. Every object the chart creates is prefixed with it."
  type        = string
  default     = "kube-prometheus-stack"
}

variable "storage_class" {
  description = "Storage class for the Prometheus and Grafana volumes. The EKS module makes ebs-sc the default class, so it is the one to use here."
  type        = string
  default     = "ebs-sc"
}

variable "prometheus_storage_size" {
  description = "Volume size for the Prometheus time series database."
  type        = string
  default     = "20Gi"
}

variable "prometheus_retention" {
  description = "How long Prometheus keeps samples. Keep it short, the volume is small."
  type        = string
  default     = "7d"
}

variable "grafana_storage_size" {
  description = "Volume size for Grafana, which stores dashboards and its own small database."
  type        = string
  default     = "5Gi"
}

variable "grafana_service_type" {
  description = "LoadBalancer gives Grafana its own address, which is the easiest thing to show a reviewer. ClusterIP keeps it inside the cluster and reachable only through kubectl port-forward."
  type        = string
  default     = "LoadBalancer"

  validation {
    condition     = contains(["LoadBalancer", "ClusterIP", "NodePort"], var.grafana_service_type)
    error_message = "grafana_service_type must be LoadBalancer, ClusterIP or NodePort."
  }
}

variable "grafana_admin_user" {
  description = "Grafana administrator user name."
  type        = string
  default     = "admin"
}

variable "grafana_admin_password" {
  description = "Grafana administrator password. Leave it null and the module generates one, readable afterwards with terraform output -raw grafana_admin_password."
  type        = string
  default     = null
  sensitive   = true
}

variable "chart_timeout" {
  description = "Seconds Helm waits for the release. The stack pulls a lot of images on a fresh cluster, so the default is generous."
  type        = number
  default     = 900
}
