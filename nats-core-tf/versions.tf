terraform {
  required_version = ">= 1.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.23"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.11"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4"
    }
  }
}

# Configure providers
provider "kubernetes" {
  config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
}

provider "helm" {
  kubernetes = {
    config_path = var.kubeconfig_path != "" ? var.kubeconfig_path : null
  }
}

