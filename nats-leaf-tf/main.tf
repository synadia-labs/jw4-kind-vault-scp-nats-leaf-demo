# Deploy NATS leaf cluster using Helm
resource "helm_release" "nats_leaf" {
  name             = "nats-leaf"
  repository       = "https://nats-io.github.io/k8s/helm/charts/"
  chart            = "nats"
  version          = var.helm_chart_version
  namespace        = var.nats_namespace
  create_namespace = false

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      cluster_size            = var.cluster_size
      jetstream_enabled       = var.jetstream_enabled
      jetstream_storage_size  = var.jetstream_storage_size
      leaf_remote_url         = var.leaf_remote_url
      enable_monitoring       = var.enable_monitoring
      resources               = var.resources
    })
  ]

  wait    = true
  timeout = 600
}