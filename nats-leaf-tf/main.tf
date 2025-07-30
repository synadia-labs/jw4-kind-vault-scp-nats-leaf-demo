# Read leaf credentials and operator config if they exist
locals {
  leaf_creds_exists = fileexists("${path.module}/.leaf.creds")
  leaf_creds        = local.leaf_creds_exists ? file("${path.module}/.leaf.creds") : ""

  operator_jwt_exists = fileexists("${path.module}/.operator-jwt")
  operator_jwt        = local.operator_jwt_exists ? file("${path.module}/.operator-jwt") : ""
  system_account      = fileexists("${path.module}/.system-account") ? file("${path.module}/.system-account") : ""
  resolver_preload    = fileexists("${path.module}/.resolver-preload") ? file("${path.module}/.resolver-preload") : "{}"
}

# Create namespace
resource "kubernetes_namespace" "nats_leaf" {
  metadata {
    name = var.nats_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "nats-leaf"
    }
  }
}

# Create secret for leaf credentials
resource "kubernetes_secret" "leaf_credentials" {
  count = local.leaf_creds_exists ? 1 : 0

  metadata {
    name      = "leaf-credentials"
    namespace = kubernetes_namespace.nats_leaf.metadata[0].name
  }

  data = {
    "leaf.creds" = local.leaf_creds
  }

  depends_on = [kubernetes_namespace.nats_leaf]
}

# Create secret for operator JWT and system account
resource "kubernetes_secret" "nats_operator" {
  count = local.operator_jwt_exists ? 1 : 0

  metadata {
    name      = "nats-operator-config"
    namespace = kubernetes_namespace.nats_leaf.metadata[0].name
  }

  data = {
    "operator.jwt"  = local.operator_jwt
    "system.creds"  = local.system_account
    "resolver.conf" = local.resolver_preload
  }

  depends_on = [kubernetes_namespace.nats_leaf]
}

# Deploy NATS leaf cluster using Helm
resource "helm_release" "nats_leaf" {
  name             = var.release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = kubernetes_namespace.nats_leaf.metadata[0].name
  create_namespace = false

  values = [
    file("${path.module}/values.yaml")
  ]

  # Wait for deployment to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = var.helm_timeout

  depends_on = [
    kubernetes_namespace.nats_leaf,
    kubernetes_secret.leaf_credentials,
    kubernetes_secret.nats_operator
  ]
}

