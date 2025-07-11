# Kubernetes Infrastructure Implementation Plan

## Overview

This project provides a simple, reliable Kubernetes cluster using KIND (Kubernetes in Docker) for local development, focusing on clarity and ease of use.

## Goals

1. **Simple**: Minimal configuration and straightforward implementation
2. **Reliable**: Consistent cluster creation and destruction
3. **Clear**: Easy to understand and modify
4. **Fast**: Quick to deploy and tear down

## Architecture

### KIND Cluster
- **Type**: Multi-node local cluster (1 control plane + 2 workers)
- **Networking**: Docker bridge network
- **Storage**: Local path provisioner (built-in)
- **Cost**: Free - runs on local Docker

### Key Features
- Metrics server for resource monitoring
- Port forwarding for service access
- Standard networking (10.244.0.0/16 pods, 10.96.0.0/12 services)
- No cloud dependencies

## Implementation

### Directory Structure
```
k8s-tf/
├── README.md           # User-facing documentation
├── IMPLEMENTATION.md   # This file
├── main.tf            # Terraform configuration
├── variables.tf       # Input variables
├── outputs.tf         # Output values
├── kind-config.yaml   # KIND cluster specification
├── deploy.sh          # Deployment script
├── destroy.sh         # Teardown script
└── .gitignore         # Git ignore rules
```

### Configuration Files

#### `variables.tf`
```hcl
variable "cluster_name" {
  description = "Name of the KIND cluster"
  type        = string
  default     = "kind-demo"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file (uses KUBECONFIG env if not set)"
  type        = string
  default     = ""
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}
```

#### `main.tf`
```hcl
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
  }
}

# Get KUBECONFIG from environment
data "external" "env" {
  program = ["sh", "-c", "echo '{\"kubeconfig\":\"'$KUBECONFIG'\"}'"]
}

locals {
  kubeconfig = var.kubeconfig_path != "" ? var.kubeconfig_path : data.external.env.result.kubeconfig
}

# Create KIND cluster
resource "null_resource" "kind_cluster" {
  provisioner "local-exec" {
    command = <<-EOT
      kind create cluster \
        --name ${var.cluster_name} \
        --config ${path.module}/kind-config.yaml \
        --kubeconfig ${local.kubeconfig} \
        --wait 5m
    EOT
    
    environment = {
      KUBECONFIG = local.kubeconfig
    }
  }
  
  provisioner "local-exec" {
    when    = destroy
    command = "kind delete cluster --name ${var.cluster_name}"
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
```

#### `outputs.tf`
```hcl
output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = var.cluster_name
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = data.external.env.result.kubeconfig
}

output "context_name" {
  description = "kubectl context name for this cluster"
  value       = "kind-${var.cluster_name}"
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://127.0.0.1:6443"
}
```

#### `kind-config.yaml`
```yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
- role: worker
- role: worker
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"
```

#### `deploy.sh`
```bash
#!/bin/bash
set -euo pipefail

# Check prerequisites
if ! command -v docker &> /dev/null; then
    echo "ERROR: Docker is not installed or not running"
    exit 1
fi

if ! command -v kind &> /dev/null; then
    echo "ERROR: KIND is not installed"
    echo "Install from: https://kind.sigs.k8s.io/docs/user/quick-start/#installation"
    exit 1
fi

if [ -z "${KUBECONFIG:-}" ]; then
    echo "ERROR: KUBECONFIG environment variable must be set"
    echo "Example: export KUBECONFIG=\$HOME/.kube/config"
    exit 1
fi

echo "Deploying KIND cluster..."
echo "  Name: kind-demo"
echo "  Kubeconfig: $KUBECONFIG"

# Create parent directory for kubeconfig if needed
mkdir -p "$(dirname "$KUBECONFIG")"

# Deploy with Terraform
terraform init
terraform apply -auto-approve

echo ""
echo "✅ Cluster deployed successfully!"
echo ""
echo "Next steps:"
echo "  kubectl config use-context kind-kind-demo"
echo "  kubectl get nodes"
```

#### `destroy.sh`
```bash
#!/bin/bash
set -euo pipefail

echo "Destroying KIND cluster..."

# Destroy with Terraform
terraform destroy -auto-approve

echo "✅ Cluster destroyed successfully!"
```

#### `.gitignore`
```
# Terraform
*.tfstate
*.tfstate.*
.terraform/
.terraform.lock.hcl
override.tf
override.tf.json
*_override.tf
*_override.tf.json

# Environment
.env
.envrc

# Logs
*.log

# OS
.DS_Store
```

### Updated User README
```markdown
# Kubernetes Infrastructure

Simple Kubernetes cluster using KIND (Kubernetes in Docker).

## Prerequisites

1. **Docker** - Must be installed and running
2. **KIND** - Install from https://kind.sigs.k8s.io
3. **kubectl** - For interacting with the cluster
4. **Terraform** - Version 1.0 or later

## Quick Start

```bash
# Set where to store kubeconfig
export KUBECONFIG=$HOME/.kube/config

# Deploy cluster
./deploy.sh

# Use cluster
kubectl get nodes

# Destroy cluster
./destroy.sh
```

## What You Get

- 3-node cluster (1 control plane, 2 workers)
- Metrics server installed
- Kubeconfig at `$KUBECONFIG`

## Configuration

Edit `terraform.tfvars` to customize:
```hcl
cluster_name = "my-cluster"
node_count   = 3
```

## Outputs

Use Terraform outputs in other projects:
```bash
terraform output cluster_name
terraform output kubeconfig_path
```
```

## Deployment Steps

### Phase 1: Environment Setup
1. Ensure Docker is running
2. Install KIND if not present
3. Set KUBECONFIG environment variable
4. Create directory: `mkdir -p $(dirname $KUBECONFIG)`

### Phase 2: Cluster Creation
1. Run `./deploy.sh`
2. Terraform will:
   - Initialize providers
   - Create KIND cluster with specified configuration
   - Wait for cluster to be ready
   - Install metrics server

### Phase 3: Validation
1. Check cluster: `kubectl cluster-info`
2. Verify nodes: `kubectl get nodes`
3. Test metrics: `kubectl top nodes`

### Phase 4: Integration
Downstream projects can:
1. Use the same KUBECONFIG
2. Read Terraform outputs
3. Deploy workloads immediately

## Best Practices

1. **Environment Isolation**
   - Use project-specific KUBECONFIG
   - Example: `export KUBECONFIG=$PWD/.kube/config`

2. **Resource Management**
   - Delete cluster when not in use
   - Monitor Docker disk usage
   - Run `docker system prune` periodically

3. **Troubleshooting**
   - Check Docker: `docker ps`
   - View KIND clusters: `kind get clusters`
   - Check logs: `docker logs kind-control-plane`

## Future Considerations

If cloud deployment is needed:
1. Create separate `k8s-tf-gke/` project
2. Keep it equally simple
3. Don't combine with this project
4. Maintain clarity over code reuse

## Summary

This implementation provides a simple, reliable Kubernetes cluster perfect for development and testing. The focus on KIND eliminates cloud dependencies while providing all necessary features. The entire implementation is under 200 lines of code, making it easy to understand and modify.