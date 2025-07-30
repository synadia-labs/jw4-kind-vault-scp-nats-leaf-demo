# Kubernetes Infrastructure

Simple Kubernetes cluster using KIND (Kubernetes in Docker) for local development.

## Prerequisites

1. **Docker** - Must be installed and running
2. **KIND** - Install from https://kind.sigs.k8s.io
3. **kubectl** - For interacting with the cluster
4. **Terraform** - Version 1.0 or later

## Quick Start

```bash
# Set where to store kubeconfig (recommended: project-specific)
export KUBECONFIG=$HOME/.kube/synadia-demo

# Deploy cluster
make up

# Check status
make status

# Use cluster
kubectl get nodes

# Destroy cluster
make down
```

## What You Get

- Multi-node cluster (1 control plane, 2 workers by default)
- Metrics server for resource monitoring
- Standard networking configuration
- Ready for application deployment

## Commands

| Command       | Description                            |
| ------------- | -------------------------------------- |
| `make help`   | Show available commands                |
| `make up`     | Create and start the cluster           |
| `make down`   | Destroy the cluster                    |
| `make status` | Show cluster status                    |
| `make clean`  | Destroy cluster and clean up all files |

## Configuration

Create `terraform.tfvars` to customize:

```hcl
cluster_name = "my-cluster"    # Default: kind-demo
node_count   = 3               # Default: 2 workers
```

## Environment Variables

- `KUBECONFIG` - **Required** - Path to store kubeconfig file
  - Recommended: Use project-specific path
  - Example: `export KUBECONFIG=$HOME/.kube/synadia-demo`

## Outputs

Use Terraform outputs in scripts or other projects:

```bash
terraform output cluster_name      # kind-demo
terraform output kubeconfig_path   # /home/user/.kube/synadia-demo
terraform output context_name      # kind-kind-demo
terraform output cluster_endpoint  # https://127.0.0.1:6443
```

## Troubleshooting

### Cluster won't start

1. Check Docker is running: `docker ps`
2. Check disk space: `docker system df`
3. Clean up: `docker system prune`

### Can't connect to cluster

1. Check KUBECONFIG: `echo $KUBECONFIG`
2. Check cluster exists: `kind get clusters`
3. Check context: `kubectl config current-context`

### View logs

```bash
# KIND logs
docker logs kind-control-plane

# Kubernetes component logs
kubectl logs -n kube-system deployment/metrics-server
```

## Next Steps

After cluster creation:

1. Deploy Vault: `cd ../vault-tf && make up`
2. Deploy SCP: `cd ../scp-tf && make up`
3. Deploy NATS: `cd ../nats-core-tf && make up`

## Notes

- The cluster runs entirely in Docker containers
- No cloud resources are created
- Perfect for local development and testing
- Automatically installs metrics server for `kubectl top`

