# Use KUBECONFIG from environment or variable

# Deploy Vault using Helm
resource "helm_release" "vault" {
  name             = "vault"
  repository       = "https://helm.releases.hashicorp.com"
  chart            = "vault"
  version          = "0.27.0"
  namespace        = var.vault_namespace
  create_namespace = true

  values = [file("${path.module}/values.yaml")]

  wait    = true
  timeout = 300
}

# Wait for Vault pod to be ready
resource "null_resource" "wait_for_vault" {
  depends_on = [helm_release.vault]

  provisioner "local-exec" {
    command = <<-EOT
      kubectl wait --for=condition=ready pod \
        -l app.kubernetes.io/name=vault \
        -n ${var.vault_namespace} \
        --timeout=120s
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Configure PKI backend
resource "null_resource" "configure_pki" {
  depends_on = [null_resource.wait_for_vault]

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/configure-pki.sh"

    environment = {
      VAULT_ADDR      = "http://localhost:8200"
      VAULT_TOKEN     = var.vault_token
      ROOT_CA_PATH    = var.root_ca_path
      VAULT_NAMESPACE = var.vault_namespace
      KUBECONFIG      = var.kubeconfig_path
    }
  }
}

# Install cert-manager
resource "null_resource" "cert_manager" {
  depends_on = [null_resource.configure_pki]

  provisioner "local-exec" {
    command = <<-EOT
      # Check if cert-manager is already installed
      if kubectl get namespace cert-manager >/dev/null 2>&1; then
        echo "cert-manager namespace already exists, skipping installation"
      else
        echo "Installing cert-manager..."
        kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${var.cert_manager_version}/cert-manager.yaml
        
        # Wait for cert-manager to be ready
        kubectl wait --for=condition=Available deployment/cert-manager -n cert-manager --timeout=300s
        kubectl wait --for=condition=Available deployment/cert-manager-webhook -n cert-manager --timeout=300s
        kubectl wait --for=condition=Available deployment/cert-manager-cainjector -n cert-manager --timeout=300s
      fi
    EOT

    environment = {
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Create ClusterIssuer
resource "null_resource" "vault_cluster_issuer" {
  depends_on = [null_resource.cert_manager]

  triggers = {
    kubeconfig = var.kubeconfig_path
  }

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for CRDs to be available
      sleep 10
      bash ${path.module}/scripts/create-issuer.sh
    EOT

    environment = {
      KUBECONFIG       = var.kubeconfig_path
      VAULT_NAMESPACE  = var.vault_namespace
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      kubectl delete clusterissuer vault-issuer --ignore-not-found=true
      kubectl delete clusterrolebinding cert-manager-vault-tokenreview --ignore-not-found=true
      kubectl delete clusterrole cert-manager-vault-tokenreview --ignore-not-found=true
      kubectl delete serviceaccount vault-issuer -n cert-manager --ignore-not-found=true
    EOT
    
    environment = {
      KUBECONFIG = self.triggers.kubeconfig
    }
  }
}