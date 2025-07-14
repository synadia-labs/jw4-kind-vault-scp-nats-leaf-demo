# Synadia Control Plane Implementation Plan

## Overview

Deploy Synadia Control Plane (SCP) for demo purposes with minimal complexity. This implementation focuses on getting SCP running quickly with basic functionality.

## Architecture

```
┌─────────────────────────┐
│   Synadia Control Plane │
│    (Single Instance)    │
└───────────┬─────────────┘
            │
      ┌─────┴─────┐
      │           │
┌─────▼─────┐ ┌──▼────────┐
│PostgreSQL │ │  Vault    │
│(Built-in) │ │(For Certs)│
└───────────┘ └───────────┘
```

## Prerequisites

1. Kubernetes cluster running (from k8s-tf)
2. Vault configured with ClusterIssuer (from vault-tf)
3. SCP works without a license for evaluation

## Implementation Steps

### Step 1: Create Namespace and License Secret

```bash
# Create namespace
kubectl create namespace scp

# No license required for evaluation
```

### Step 2: Deploy SCP via Helm

Simple values.yaml for demo:

```yaml
# values.yaml
global:
  # No license configuration required for evaluation

controlPlane:
  # Single instance for demo
  replicas: 1

  # Use NodePort for easy access
  service:
    type: NodePort
    nodePort: 30080

  # Simple resource limits
  resources:
    requests:
      memory: 512Mi
      cpu: 250m
    limits:
      memory: 1Gi
      cpu: 1000m

# Use embedded database for demo
postgresql:
  enabled: true
  persistence:
    size: 10Gi

# Disable complex features for demo
monitoring:
  enabled: false

ingress:
  enabled: false
```

Deploy with Helm:

```bash
helm repo add synadia https://synadia-io.github.io/helm-charts
helm repo update

helm install scp synadia/control-plane \
  --namespace scp \
  --values values.yaml
```

### Step 3: Initialize Admin User

```bash
# Wait for SCP to be ready
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=control-plane -n scp --timeout=300s

# Port forward to access SCP
kubectl port-forward -n scp svc/scp-control-plane 8080:80 &

# Generate admin password
ADMIN_PWD=$(openssl rand -base64 16)

# Create admin user with token
RESPONSE=$(curl -X POST http://localhost:8080/api/core/beta/admin/app-user \
  -H "Content-Type: application/json" \
  -H "Accept: application/json" \
  -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PWD\",\"generate_token\":true}")

# Extract token
export SCP_TOKEN=$(echo "$RESPONSE" | jq -r '.token')
```

### Step 4: Store Credentials

Create a Kubernetes secret with credentials:

```bash
kubectl create secret generic scp-credentials \
  --from-literal=admin-password="$ADMIN_PWD" \
  --from-literal=api-token="$SCP_TOKEN" \
  --from-literal=api-url="http://scp-control-plane.scp:8080" \
  -n scp
```

### Step 5: Create Demo Team and System

```bash
# Create team
curl -X POST http://localhost:8080/api/core/beta/teams \
  -H "Authorization: Bearer $SCP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-team"}' \
  -o team.json

TEAM_ID=$(jq -r '.id' team.json)

# Create system
curl -X POST "http://localhost:8080/api/core/beta/teams/$TEAM_ID/systems" \
  -H "Authorization: Bearer $SCP_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"name":"demo-system","description":"Demo System"}' \
  -o system.json

SYSTEM_ID=$(jq -r '.id' system.json)
```

## Terraform Implementation

### Directory Structure

```
scp-tf/
├── main.tf              # Main configuration
├── variables.tf         # Input variables
├── outputs.tf          # Output values
├── versions.tf         # Provider versions
├── values.yaml         # Helm values
├── scripts/
│   └── init-admin.sh   # Admin initialization script
└── Makefile            # Simple commands
```

### main.tf

```hcl
# Deploy SCP using Helm
resource "helm_release" "scp" {
  name             = "scp"
  repository       = "https://synadia-io.github.io/helm-charts"
  chart            = "control-plane"
  namespace        = var.scp_namespace
  create_namespace = true

  values = [file("${path.module}/values.yaml")]

  # No license configuration required
}

# Initialize admin and get credentials
resource "null_resource" "init_admin" {
  depends_on = [helm_release.scp]

  provisioner "local-exec" {
    command = "bash ${path.module}/scripts/init-admin.sh"

    environment = {
      NAMESPACE  = var.scp_namespace
      KUBECONFIG = var.kubeconfig_path
    }
  }
}

# Store credentials as secret
resource "kubernetes_secret" "scp_credentials" {
  depends_on = [null_resource.init_admin]

  metadata {
    name      = "scp-credentials"
    namespace = var.scp_namespace
  }

  data = {
    admin-password = file("${path.module}/.admin-password")
    api-token      = file("${path.module}/.api-token")
    api-url        = "http://scp-control-plane.${var.scp_namespace}:8080"
  }
}
```

## Usage

### Quick Start

```bash
# Deploy SCP
make apply

# Get admin password
make get-password

# Access UI
make port-forward
# Browse to http://localhost:8080
```

### Access API

```bash
# Get API token
export SCP_TOKEN=$(kubectl get secret -n scp scp-credentials \
  -o jsonpath='{.data.api-token}' | base64 -d)

# List teams
curl -H "Authorization: Bearer $SCP_TOKEN" \
  http://localhost:8080/api/core/beta/teams
```

## Outputs

- `admin_password`: Admin user password
- `api_token`: API token for automation
- `api_url`: SCP API endpoint
- `console_url`: Web UI access URL

## Notes for Demo

1. **Simplifications:**
   - Single instance (no HA)
   - Built-in PostgreSQL
   - NodePort for easy access
   - No monitoring/metrics
   - Basic auth only

2. **Security:**
   - This is for DEMO only
   - Use proper ingress with TLS in production
   - Enable RBAC and MFA in production
   - Rotate credentials regularly

3. **Next Steps:**
   - Create NATS systems via SCP
   - Configure accounts and users
   - Generate NATS configurations

