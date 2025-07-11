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
make up

# Use cluster
kubectl get nodes

# Destroy cluster
make down
```

## What You Get

- 3-node cluster (1 control plane, 2 workers by default)
- Metrics server for resource monitoring
- Kubeconfig at `$KUBECONFIG`
- Ready for application deployment

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