terraform {
  required_version = ">= 1.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    external = {
      source  = "hashicorp/external"
      version = "~> 2.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.4"
    }
  }
}

# Get KUBECONFIG from environment
data "external" "env" {
  program = ["sh", "-c", "echo '{\"kubeconfig\":\"'$KUBECONFIG'\"}'"]
}

locals {
  kubeconfig   = var.kubeconfig_path != "" ? var.kubeconfig_path : data.external.env.result.kubeconfig
  cluster_name = var.cluster_name
}

# Validate KUBECONFIG is set
resource "null_resource" "validate_kubeconfig" {
  provisioner "local-exec" {
    command = <<-EOT
      if [ -z "${local.kubeconfig}" ]; then
        echo "ERROR: KUBECONFIG environment variable must be set or kubeconfig_path variable must be provided"
        exit 1
      fi
      
      # Ensure directory exists
      mkdir -p "$(dirname ${local.kubeconfig})"
    EOT
  }
}

# Generate KIND config with dynamic node count
resource "local_file" "kind_config" {
  filename = "${path.module}/kind-config-generated.yaml"
  content = templatefile("${path.module}/kind-config.yaml.tpl", {
    node_count = var.node_count
  })
}

# Create KIND cluster
resource "null_resource" "kind_cluster" {
  depends_on = [local_file.kind_config, null_resource.validate_kubeconfig]

  triggers = {
    cluster_name   = local.cluster_name
    config_content = local_file.kind_config.content
  }

  provisioner "local-exec" {
    command = <<-EOT
      kind create cluster \
        --name ${local.cluster_name} \
        --config ${path.module}/kind-config-generated.yaml \
        --kubeconfig ${local.kubeconfig} \
        --wait 5m
    EOT

    environment = {
      KUBECONFIG = local.kubeconfig
    }
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kind delete cluster --name ${self.triggers.cluster_name}"
  }
}

# Install essential cluster components
resource "null_resource" "cluster_setup" {
  depends_on = [null_resource.kind_cluster]

  provisioner "local-exec" {
    command = <<-EOT
      # Wait for cluster to be ready
      kubectl wait --for=condition=Ready nodes --all --timeout=300s
      
      # Install metrics server
      kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
      
      # Patch metrics server for KIND
      kubectl patch deployment metrics-server -n kube-system --type='json' \
        -p='[{"op": "add", "path": "/spec/template/spec/containers/0/args/-", "value": "--kubelet-insecure-tls"}]'
    EOT

    environment = {
      KUBECONFIG = local.kubeconfig
    }
  }
}