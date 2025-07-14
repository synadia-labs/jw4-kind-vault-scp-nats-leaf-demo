# Example Terraform variables file

# Path to kubeconfig (optional, uses KUBECONFIG env var by default)
# kubeconfig_path = "/path/to/kubeconfig"


# Custom NodePort (default is 30080)
# node_port = 30080

# Create demo team and project (default is true)
# create_demo_team = true

# Specific chart version (default is latest)
# scp_chart_version = "1.0.0"

# Custom Helm repository (default is https://synadia-io.github.io/helm-charts)
# synadia_helm_repository = "https://custom-helm-repo.com"

# Custom image configuration
# scp_image_repository = "myregistry.io/synadia/control-plane"
# scp_image_tag = "1.2.3"
# scp_image_pull_policy = "Always"

# Image pull secrets (list of existing secret names)
# scp_image_pull_secrets = ["my-existing-pull-secret"]

# Docker registry credentials for creating pull secret
# docker_registry_secret = jsonencode({
#   auths = {
#     "myregistry.io" = {
#       auth = base64encode("username:password")
#     }
#   }
# })