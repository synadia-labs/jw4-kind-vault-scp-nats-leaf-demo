# Create namespace
resource "kubernetes_namespace" "scp" {
  metadata {
    name = var.scp_namespace
  }
}

# Create image pull secret if docker registry credentials are provided
resource "kubernetes_secret" "docker_registry" {
  count = var.docker_registry_secret != "" ? 1 : 0

  metadata {
    name      = "scp-docker-registry"
    namespace = kubernetes_namespace.scp.metadata[0].name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = var.docker_registry_secret
  }
}

# Deploy SCP using Helm
resource "helm_release" "scp" {
  name             = "scp"
  repository       = var.synadia_helm_repository
  chart            = "control-plane"
  version          = var.scp_chart_version != "" ? var.scp_chart_version : null
  namespace        = kubernetes_namespace.scp.metadata[0].name
  create_namespace = false # We already created it

  values = [
    templatefile("${path.module}/values.yaml.tpl", {
      node_port         = var.node_port
      image_repository  = var.scp_image_repository
      image_registry    = var.scp_image_registry
      image_tag         = var.scp_image_tag
      image_pull_policy = var.scp_image_pull_policy
      username          = var.scp_image_username
      password          = var.scp_image_password
    })
  ]

  wait    = true
  timeout = 600

  depends_on = [kubernetes_secret.docker_registry]
}

# Initialize admin and get credentials
resource "null_resource" "init_admin" {
  depends_on = [helm_release.scp]

  triggers = {
    namespace = var.scp_namespace
  }

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/init-admin.sh"

    environment = {
      NAMESPACE        = var.scp_namespace
      KUBECONFIG       = var.kubeconfig_path
      CREATE_DEMO_TEAM = var.create_demo_team ? "true" : "false"
    }
  }
}

# Note: Credentials are stored in local files by init script
# and can be accessed via the outputs
