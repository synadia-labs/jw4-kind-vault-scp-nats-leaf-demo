# Data source to read SCP credentials
data "kubernetes_secret" "scp_credentials" {
  metadata {
    name      = "scp-credentials"
    namespace = var.scp_namespace
  }
}

# Read operator config files if they exist
locals {
  operator_jwt_exists = fileexists("${path.module}/.operator-jwt")
  operator_jwt        = local.operator_jwt_exists ? file("${path.module}/.operator-jwt") : ""
  system_account      = fileexists("${path.module}/.system-account") ? file("${path.module}/.system-account") : ""
  resolver_preload    = fileexists("${path.module}/.resolver-preload") ? file("${path.module}/.resolver-preload") : "{}"
}

# Create namespace if specified
resource "kubernetes_namespace" "nats" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.nats_namespace

    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "app.kubernetes.io/part-of"    = "nats"
    }
  }
}

# Create secret for operator JWT and system account
resource "kubernetes_secret" "nats_operator" {
  count = local.operator_jwt_exists ? 1 : 0

  metadata {
    name      = "nats-operator-config"
    namespace = var.nats_namespace
  }

  data = {
    "operator.jwt"  = local.operator_jwt
    "system.creds"  = local.system_account
    "resolver.conf" = local.resolver_preload
  }

  depends_on = [kubernetes_namespace.nats]
}

# Deploy NATS using Helm
resource "helm_release" "nats" {
  name             = var.release_name
  repository       = var.nats_helm_repository
  chart            = var.nats_helm_chart
  version          = var.nats_chart_version
  namespace        = var.nats_namespace
  create_namespace = false # We handle namespace creation separately

  values = [
    file("${path.module}/values.yaml")
  ]

  # Wait for deployment to be ready
  wait          = true
  wait_for_jobs = true
  timeout       = var.helm_timeout

  depends_on = [
    kubernetes_namespace.nats,
    kubernetes_secret.nats_operator
  ]
}

# Create a service monitor for Prometheus if enabled
resource "kubernetes_manifest" "nats_service_monitor" {
  count = var.enable_monitoring ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"

    metadata = {
      name      = "${var.release_name}-metrics"
      namespace = var.nats_namespace
      labels = {
        "app.kubernetes.io/name"       = "nats"
        "app.kubernetes.io/instance"   = var.release_name
        "app.kubernetes.io/managed-by" = "terraform"
      }
    }

    spec = {
      selector = {
        matchLabels = {
          "app.kubernetes.io/name"     = "nats"
          "app.kubernetes.io/instance" = var.release_name
        }
      }

      endpoints = [
        {
          port = "metrics"
          path = "/metrics"
        }
      ]
    }
  }

  depends_on = [helm_release.nats]
}

