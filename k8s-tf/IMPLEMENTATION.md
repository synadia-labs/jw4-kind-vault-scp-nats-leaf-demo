# Kubernetes Infrastructure Implementation

## Overview

This project provides a simple, reliable Kubernetes cluster using KIND (Kubernetes in Docker) for local development, focusing on clarity and ease of use.

## Goals

1. **Simple**: Minimal configuration and straightforward implementation
2. **Reliable**: Consistent cluster creation and destruction
3. **Clear**: Easy to understand and modify
4. **Fast**: Quick to deploy and tear down

## Architecture

### KIND Cluster

- **Type**: Multi-node local cluster (1 control plane + configurable workers)
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
├── README.md               # User-facing documentation
├── IMPLEMENTATION.md       # This file
├── Makefile               # Simplified commands
├── main.tf                # Terraform configuration
├── variables.tf           # Input variables
├── outputs.tf             # Output values
├── kind-config.yaml.tpl   # KIND cluster template
└── .gitignore             # Git ignore rules
```

### Key Components

#### Makefile

Provides simple commands for cluster management:

- `make up` - Create and start the cluster
- `make down` - Destroy the cluster
- `make status` - Show cluster status
- `make clean` - Destroy cluster and clean up files
- `make help` - Show available commands

#### Terraform Configuration

The project uses Terraform with three providers:

- **null** - For executing local commands
- **external** - For reading environment variables
- **local** - For generating configuration files

Key resources:

1. **validate_kubeconfig** - Ensures KUBECONFIG is set
2. **kind_config** - Generates KIND configuration from template
3. **kind_cluster** - Creates/destroys the KIND cluster
4. **cluster_setup** - Installs metrics server

#### KIND Configuration Template

Uses a template (`kind-config.yaml.tpl`) to generate the cluster configuration:

- 1 control plane node
- Configurable number of worker nodes (default: 2)
- Standard Kubernetes networking

## Configuration Variables

| Variable        | Description              | Default              |
| --------------- | ------------------------ | -------------------- |
| cluster_name    | Name of the KIND cluster | kind-demo            |
| kubeconfig_path | Path to kubeconfig file  | Uses $KUBECONFIG env |
| node_count      | Number of worker nodes   | 2                    |

## Outputs

| Output           | Description                    |
| ---------------- | ------------------------------ |
| cluster_name     | Name of the Kubernetes cluster |
| kubeconfig_path  | Path to the kubeconfig file    |
| context_name     | kubectl context name           |
| cluster_endpoint | Kubernetes API endpoint        |

## Deployment Process

### Prerequisites Check

The Makefile checks for:

- Docker (installed and running)
- KIND
- kubectl
- Terraform

### Cluster Creation

1. Validates KUBECONFIG environment variable
2. Generates KIND configuration from template
3. Creates KIND cluster with specified configuration
4. Waits for cluster to be ready
5. Installs and patches metrics server for KIND

### Cluster Destruction

1. Deletes KIND cluster
2. Cleans up generated files (optional with `make clean`)

## Best Practices

1. **Environment Isolation**
   - Use project-specific KUBECONFIG
   - Example: `export KUBECONFIG=$HOME/.kube/synadia-demo`

2. **Resource Management**
   - Delete cluster when not in use
   - Monitor Docker disk usage
   - Run `docker system prune` periodically

3. **Troubleshooting**
   - Check Docker: `docker ps`
   - View KIND clusters: `kind get clusters`
   - Check logs: `docker logs kind-control-plane`
   - Use `make status` to check cluster state

## Integration with Other Projects

Downstream projects can:

1. Use the same KUBECONFIG
2. Read Terraform outputs
3. Deploy workloads immediately

Example in another Terraform project:

```hcl
data "terraform_remote_state" "k8s" {
  backend = "local"
  config = {
    path = "../k8s-tf/terraform.tfstate"
  }
}

# Use: data.terraform_remote_state.k8s.outputs.cluster_name
```

## Summary

This implementation provides a simple, reliable Kubernetes cluster perfect for development and testing. The focus on KIND eliminates cloud dependencies while providing all necessary features. The Makefile interface makes it extremely easy to use, while Terraform provides proper state management and repeatability.

