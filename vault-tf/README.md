# Vault Infrastructure

## Overview

Deploys HashiCorp Vault in development mode with PKI backend configured to issue certificates via cert-manager. The PKI intermediate CA is signed by an external root CA that you provide.

## Prerequisites

1. Kubernetes cluster running (from k8s-tf)
2. Root CA files:
   - `${ROOT_CA_PATH}/root-ca.crt` - Root certificate
   - `${ROOT_CA_PATH}/root-ca.key` - Root private key
3. Tools installed:
   - terraform >= 1.0
   - kubectl
   - vault CLI (optional)

## Quick Start

```bash
# Set root CA path
export ROOT_CA_PATH=/path/to/your/ca/files

# Initialize and deploy
make init
make apply

# Check status
make status

# Access Vault UI
make port-forward
# Then browse to http://localhost:30200 (token: root)
```

## What Gets Deployed

- **Vault** in dev mode (auto-unsealed, token: "root")
- **PKI Backend** with intermediate CA signed by your root CA
- **cert-manager** for automatic certificate management
- **ClusterIssuer** named "vault-issuer"

## Usage Examples

### Request Certificate via cert-manager

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: my-app-cert
  namespace: default
spec:
  secretName: my-app-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: myapp.demo.local
  dnsNames:
  - myapp.demo.local
  - myapp.svc.cluster.local
  duration: 720h
  renewBefore: 240h
```

### Test Certificate Creation

```bash
# Create a test certificate
make test-cert

# Check certificate details
kubectl get certificate vault-demo-cert -n default
kubectl describe certificate vault-demo-cert -n default
```

### Manual Certificate Request

```bash
# Port forward to Vault
kubectl port-forward -n vault svc/vault 8200:8200

# Set Vault address and token
export VAULT_ADDR="http://localhost:8200"
export VAULT_TOKEN="root"

# Request a certificate
vault write pki_int/issue/kubernetes \
  common_name="myservice.demo.local" \
  ttl="24h"
```

## Available Commands

```bash
make help        # Show all available commands
make init        # Initialize Terraform
make plan        # Show what will be deployed
make apply       # Deploy Vault and configure PKI
make destroy     # Remove all resources
make status      # Check deployment status
make test-cert   # Create a test certificate
make logs        # Show Vault logs
make vault-cli   # Open Vault CLI in pod
```

## Architecture

```
External Root CA (files)
    ↓ signs
Vault Intermediate CA
    ↓ issues via
cert-manager ClusterIssuer
    ↓ creates
Kubernetes TLS Secrets
```

## Configuration

The PKI backend is configured to:
- Allow domains: `*.cluster.local`, `*.svc.cluster.local`, `*.demo.local`
- Allow subdomains and bare domains
- Allow localhost and IP SANs
- Default TTL: 24 hours
- Max TTL: 720 hours (30 days)

## Troubleshooting

### Check Vault Status
```bash
kubectl get pods -n vault
kubectl logs -n vault -l app.kubernetes.io/name=vault
```

### Check cert-manager
```bash
kubectl get pods -n cert-manager
kubectl logs -n cert-manager -l app.kubernetes.io/name=cert-manager
```

### Verify ClusterIssuer
```bash
kubectl describe clusterissuer vault-issuer
```

### Test PKI Manually
```bash
make vault-cli
# Inside the pod:
vault login root
vault write pki_int/issue/kubernetes common_name=test.local
```

## Security Notes

- This uses Vault in **dev mode** - suitable for demos only
- Root token is "root" - not for production use
- Wildcard service account bindings - restrict in production
- No TLS on Vault listener - enable in production