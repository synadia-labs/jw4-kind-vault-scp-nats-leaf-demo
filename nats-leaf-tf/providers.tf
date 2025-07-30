# Configure Kubernetes provider
provider "kubernetes" {
  # Use the KUBECONFIG environment variable
}

# Configure Helm provider  
provider "helm" {
  kubernetes {
    # Use the KUBECONFIG environment variable
  }
}