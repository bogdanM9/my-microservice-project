# ---------------------------------------------------------------------------
# Argo CD itself
# ---------------------------------------------------------------------------
resource "helm_release" "argo_cd" {
  name       = var.name
  namespace  = var.namespace
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.chart_version

  create_namespace = true

  timeout = 900
  wait    = true

  values = [
    file("${path.module}/values.yaml")
  ]
}

# ---------------------------------------------------------------------------
# Repository credentials
#
# Argo CD reads repository connections from Secrets labelled
# argocd.argoproj.io/secret-type=repository. This one lets it clone the private
# repository with the same PAT Jenkins uses.
#
# Written as a kubernetes_secret rather than through the Helm chart below so
# that Terraform marks it sensitive and it never shows up in plan output.
# ---------------------------------------------------------------------------
resource "kubernetes_secret" "repository" {
  metadata {
    name      = "repo-${var.name}"
    namespace = var.namespace

    labels = {
      "argocd.argoproj.io/secret-type" = "repository"
    }
  }

  data = {
    type     = "git"
    url      = var.github_repo_url
    username = var.github_username
    password = var.github_token
  }

  depends_on = [helm_release.argo_cd]
}

# ---------------------------------------------------------------------------
# The Application
#
# Installed as a small local Helm chart so that adding a second application
# later is a matter of adding one entry to charts/values.yaml, instead of
# copying a whole Terraform resource.
# ---------------------------------------------------------------------------
resource "helm_release" "argo_apps" {
  name      = "${var.name}-apps"
  chart     = "${path.module}/charts"
  namespace = var.namespace

  create_namespace = false

  values = [
    templatefile("${path.module}/charts/values.yaml", {
      app_name        = var.app_name
      namespace       = var.namespace
      github_repo_url = var.github_repo_url
      chart_path      = var.chart_path
      git_branch      = var.git_branch
      destination_ns  = var.destination_namespace
    })
  ]

  depends_on = [
    helm_release.argo_cd,
    kubernetes_secret.repository,
  ]
}
