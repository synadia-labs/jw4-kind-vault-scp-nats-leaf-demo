# Synadia Control Plane (SCP)

## Overview

Deploys Synadia Control Plane for centralized NATS management. This demo configuration provides a simple single-instance deployment suitable for development and testing.

## Prerequisites

- Kubernetes cluster (from k8s-tf)
- Vault with ClusterIssuer (from vault-tf)
- Docker registry credentials (optional - for private image registries)

## Quick Start

```bash

# Deploy SCP
make apply

# Or with custom image and registry credentials
make apply TF_VAR_scp_image_repository=myregistry.io/synadia/control-plane \
           TF_VAR_scp_image_tag=1.2.3 \
           TF_VAR_docker_registry_secret='{"auths":{"myregistry.io":{"auth":"base64_encoded_credentials"}}}'

# Get admin credentials
make get-credentials

# Access UI
make port-forward
# Browse to http://localhost:30080
```

## What Gets Deployed

- **Synadia Control Plane** (single instance)
- **PostgreSQL** (embedded database)
- **Admin credentials** stored as Kubernetes secret
- **NodePort service** for easy access

## Outputs

- `admin_password`: Admin user password
- `api_token`: API token for automation
- `api_url`: SCP API endpoint URL
- `console_url`: Web console URL (http://localhost:30080)

## Usage Examples

### Access Web UI
```bash
make port-forward
# Login with admin credentials
# Username: admin
# Password: (from make get-credentials)
```

### Use API
```bash
# Get API token
export SCP_TOKEN=$(make get-token)

# List teams
curl -H "Authorization: Bearer $SCP_TOKEN" \
  http://localhost:30080/api/core/beta/teams
```

## Available Commands

```bash
make help           # Show all commands
make apply          # Deploy SCP
make destroy        # Remove SCP
make get-credentials # Show admin credentials
make port-forward   # Access UI locally
make logs           # Show SCP logs
```

## Configuration Variables

### Helm Repository
- `synadia_helm_repository`: Custom Helm repository URL (default: `https://synadia-io.github.io/helm-charts`)

### Image Configuration
- `scp_image_repository`: Docker image repository (default: `synadia/control-plane`)
- `scp_image_tag`: Docker image tag (default: chart default)
- `scp_image_pull_policy`: Image pull policy (default: `IfNotPresent`)
- `scp_image_pull_secrets`: List of existing image pull secret names
- `docker_registry_secret`: Docker registry auth JSON for creating pull secret

### Example: Using Private Registry
```bash
# Create docker config JSON
export DOCKER_AUTH=$(echo -n "username:password" | base64)
export DOCKER_CONFIG_JSON='{"auths":{"myregistry.io":{"auth":"'$DOCKER_AUTH'"}}}'

# Deploy with custom image
make apply TF_VAR_scp_image_repository=myregistry.io/synadia/control-plane \
           TF_VAR_scp_image_tag=1.2.3 \
           TF_VAR_docker_registry_secret="$DOCKER_CONFIG_JSON"

# Or with custom Helm repository
make apply TF_VAR_synadia_helm_repository=https://custom-helm-repo.com
```

## Notes

- This is a **demo configuration** - not for production
- Uses NodePort for simplicity (production should use Ingress)
- Single instance (production should use HA)
- Credentials are stored in Kubernetes secrets