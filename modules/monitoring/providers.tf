# The module needs the Kubernetes and Helm providers, both configured by the
# root module against the cluster, and random for the Grafana password. They are
# declared rather than configured here: a module that configures its own
# provider cannot be removed cleanly, which is a documented Terraform trap.
terraform {
  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.12"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.25"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}
