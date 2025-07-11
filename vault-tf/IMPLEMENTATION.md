# Vault Infrastructure Implementation Plan

## Architecture Overview

This project deploys and configures HashiCorp Vault on Kubernetes to provide PKI services for the entire infrastructure. Vault will manage certificate generation for both Kubernetes services and IoT devices connecting via mTLS.

## Architecture Components

### 1. Vault Deployment
- **Installation Method**: Helm chart with HA configuration
- **Storage Backend**: Consul or integrated storage (Raft)
- **High Availability**: 3-node cluster with auto-unseal
- **TLS**: End-to-end encryption for all communications

### 2. PKI Architecture
- **Root CA**: Offline root certificate authority
- **Intermediate CA**: Online intermediate for day-to-day operations
- **Certificate Types**:
  - Kubernetes service certificates
  - Device client certificates for mTLS
  - NATS cluster certificates
  - Auth service certificates

### 3. Authentication Methods
- **Kubernetes Auth**: For pod authentication
- **AppRole**: For external service authentication
- **Token**: For administrative access
- **TLS Certificates**: For device authentication

### 4. Security Architecture
- **Auto-unseal**: Using GCP KMS
- **Audit Logging**: All operations logged
- **Policy-based Access**: Least privilege model
- **Dynamic Secrets**: Short-lived credentials

## Implementation Steps

### Phase 1: Prerequisites

1. **Kubernetes Cluster Access**
   ```bash
   # Verify cluster access
   kubectl cluster-info
   kubectl get nodes
   
   # Create vault namespace
   kubectl create namespace vault
   ```

2. **GCP KMS Setup for Auto-unseal**
   ```bash
   # Create KMS keyring
   gcloud kms keyrings create vault-keyring \
     --location global
   
   # Create encryption key
   gcloud kms keys create vault-key \
     --location global \
     --keyring vault-keyring \
     --purpose encryption
   
   # Create service account for auto-unseal
   gcloud iam service-accounts create vault-kms
   ```

3. **Storage Backend Decision**
   - Option A: Integrated Storage (Raft) - Recommended
   - Option B: Consul backend
   - Option C: Cloud SQL backend

### Phase 2: Terraform Configuration

1. **Directory Structure**
   ```
   vault-tf/
   ├── main.tf              # Vault deployment
   ├── variables.tf         # Input variables
   ├── outputs.tf          # Output values
   ├── helm.tf             # Helm provider and release
   ├── pki.tf              # PKI configuration
   ├── auth.tf             # Auth methods setup
   ├── policies.tf         # Vault policies
   ├── kms.tf              # Auto-unseal configuration
   └── scripts/
       ├── init-vault.sh    # Initialization script
       └── configure-pki.sh # PKI setup script
   ```

2. **Helm Values Configuration**
   ```yaml
   server:
     ha:
       enabled: true
       replicas: 3
       raft:
         enabled: true
     
     extraSecretEnvironmentVars:
       - envName: GOOGLE_APPLICATION_CREDENTIALS
         secretName: vault-gcp-sa
         secretKey: credentials.json
   ```

### Phase 3: Vault Deployment

1. **Deploy Vault via Helm** (`helm.tf`)
   ```hcl
   resource "helm_release" "vault" {
     name       = "vault"
     namespace  = "vault"
     repository = "https://helm.releases.hashicorp.com"
     chart      = "vault"
     version    = var.vault_helm_version
     
     values = [
       templatefile("${path.module}/values.yaml", {
         kms_project     = var.gcp_project
         kms_region      = var.gcp_region
         kms_key_ring    = google_kms_key_ring.vault.name
         kms_crypto_key  = google_kms_crypto_key.vault_key.name
       })
     ]
   }
   ```

2. **Configure Auto-unseal** (`kms.tf`)
   ```hcl
   seal "gcpckms" {
     project     = var.gcp_project
     region      = var.gcp_region
     key_ring    = google_kms_key_ring.vault.name
     crypto_key  = google_kms_crypto_key.vault_key.name
   }
   ```

### Phase 4: Vault Initialization

1. **Initialize Vault Cluster**
   ```bash
   # Port forward to Vault
   kubectl port-forward -n vault vault-0 8200:8200
   
   # Initialize Vault
   vault operator init \
     -key-shares=5 \
     -key-threshold=3 \
     -format=json > vault-init.json
   
   # Store root token securely
   export VAULT_TOKEN=$(cat vault-init.json | jq -r '.root_token')
   ```

2. **Configure HA Cluster**
   ```bash
   # Join other nodes to cluster
   kubectl exec -n vault vault-1 -- vault operator raft join http://vault-0.vault-internal:8200
   kubectl exec -n vault vault-2 -- vault operator raft join http://vault-0.vault-internal:8200
   ```

### Phase 5: PKI Configuration

1. **Enable PKI Secrets Engine** (`pki.tf`)
   ```hcl
   resource "vault_mount" "root_ca" {
     path = "pki-root"
     type = "pki"
     max_lease_ttl_seconds = 315360000  # 10 years
   }
   
   resource "vault_mount" "intermediate_ca" {
     path = "pki-int"
     type = "pki"
     max_lease_ttl_seconds = 157680000  # 5 years
   }
   ```

2. **Generate Root CA**
   ```bash
   # Generate root certificate
   vault write -field=certificate pki-root/root/generate/internal \
     common_name="Synadia Demo Root CA" \
     ttl=87600h > root_ca.crt
   
   # Configure root CA URLs
   vault write pki-root/config/urls \
     issuing_certificates="https://vault.vault:8200/v1/pki-root/ca" \
     crl_distribution_points="https://vault.vault:8200/v1/pki-root/crl"
   ```

3. **Configure Intermediate CA**
   ```bash
   # Generate intermediate CSR
   vault write -format=json pki-int/intermediate/generate/internal \
     common_name="Synadia Demo Intermediate CA" \
     | jq -r '.data.csr' > int.csr
   
   # Sign intermediate certificate
   vault write -format=json pki-root/root/sign-intermediate \
     csr=@int.csr \
     format=pem_bundle ttl="43800h" \
     | jq -r '.data.certificate' > int.crt
   
   # Set signed certificate
   vault write pki-int/intermediate/set-signed certificate=@int.crt
   ```

### Phase 6: Certificate Roles Configuration

1. **Kubernetes Service Certificates Role**
   ```hcl
   resource "vault_pki_secret_backend_role" "kubernetes" {
     backend = vault_mount.intermediate_ca.path
     name    = "kubernetes-svc"
     
     allowed_domains = [
       "svc.cluster.local",
       "vault.vault.svc.cluster.local"
     ]
     allow_subdomains = true
     allow_glob_domains = true
     generate_lease = false
     ttl = "720h"
     max_ttl = "8760h"
   }
   ```

2. **Device mTLS Certificates Role**
   ```hcl
   resource "vault_pki_secret_backend_role" "device_mtls" {
     backend = vault_mount.intermediate_ca.path
     name    = "device-mtls"
     
     allowed_domains = ["device.synadia.local"]
     allow_subdomains = true
     allow_any_name = false
     enforce_hostnames = false
     allow_ip_sans = false
     client_flag = true
     ttl = "168h"  # 7 days
     max_ttl = "720h"  # 30 days
   }
   ```

3. **NATS Cluster Certificates Role**
   ```hcl
   resource "vault_pki_secret_backend_role" "nats_cluster" {
     backend = vault_mount.intermediate_ca.path
     name    = "nats-cluster"
     
     allowed_domains = [
       "nats.nats.svc.cluster.local",
       "*.nats.nats.svc.cluster.local"
     ]
     allow_subdomains = true
     allow_bare_domains = true
     allow_glob_domains = true
     ttl = "720h"
     max_ttl = "8760h"
   }
   ```

### Phase 7: Authentication Configuration

1. **Enable Kubernetes Auth** (`auth.tf`)
   ```hcl
   resource "vault_auth_backend" "kubernetes" {
     type = "kubernetes"
   }
   
   resource "vault_kubernetes_auth_backend_config" "config" {
     backend            = vault_auth_backend.kubernetes.path
     kubernetes_host    = var.kubernetes_host
     kubernetes_ca_cert = var.kubernetes_ca_cert
     token_reviewer_jwt = var.kubernetes_token
   }
   ```

2. **Configure Kubernetes Roles**
   ```hcl
   resource "vault_kubernetes_auth_backend_role" "nats" {
     backend                          = vault_auth_backend.kubernetes.path
     role_name                        = "nats"
     bound_service_account_names      = ["nats"]
     bound_service_account_namespaces = ["nats"]
     token_ttl                        = 3600
     token_policies                   = ["nats-policy"]
   }
   ```

3. **Enable AppRole for Devices**
   ```hcl
   resource "vault_auth_backend" "approle" {
     type = "approle"
   }
   
   resource "vault_approle_auth_backend_role" "device" {
     backend        = vault_auth_backend.approle.path
     role_name      = "device"
     token_policies = ["device-policy"]
     token_ttl      = 1800
     token_max_ttl  = 3600
   }
   ```

### Phase 8: Policy Configuration

1. **NATS Policy** (`policies.tf`)
   ```hcl
   resource "vault_policy" "nats" {
     name = "nats-policy"
     
     policy = <<EOT
   path "pki-int/issue/nats-cluster" {
     capabilities = ["create", "update"]
   }
   
   path "pki-int/certs" {
     capabilities = ["list"]
   }
   EOT
   }
   ```

2. **Device Policy**
   ```hcl
   resource "vault_policy" "device" {
     name = "device-policy"
     
     policy = <<EOT
   path "pki-int/issue/device-mtls" {
     capabilities = ["create", "update"]
   }
   
   path "auth/token/renew-self" {
     capabilities = ["update"]
   }
   EOT
   }
   ```

### Phase 9: Kubernetes Integration

1. **Create ServiceAccount and ClusterRoleBinding**
   ```yaml
   apiVersion: v1
   kind: ServiceAccount
   metadata:
     name: vault-auth
     namespace: vault
   ---
   apiVersion: rbac.authorization.k8s.io/v1
   kind: ClusterRoleBinding
   metadata:
     name: vault-auth-delegator
   roleRef:
     apiGroup: rbac.authorization.k8s.io
     kind: ClusterRole
     name: system:auth-delegator
   subjects:
   - kind: ServiceAccount
     name: vault-auth
     namespace: vault
   ```

2. **Configure Vault Injector**
   - Enable sidecar injection
   - Configure annotations for certificate injection

### Phase 10: Output Configuration

1. **Essential Outputs** (`outputs.tf`)
   ```hcl
   output "vault_endpoint" {
     value = "https://vault.vault.svc.cluster.local:8200"
   }
   
   output "ca_certificate" {
     value = vault_pki_secret_backend_root_cert.root.certificate
   }
   
   output "vault_credentials_file" {
     value = local_file.vault_creds.filename
   }
   ```

2. **Generate Credentials File**
   ```hcl
   resource "local_file" "vault_creds" {
     content = jsonencode({
       vault_addr = "https://vault.vault.svc.cluster.local:8200"
       vault_token = var.vault_token
       ca_cert_path = "/vault/ca/ca.crt"
       pki_mount_paths = {
         root = vault_mount.root_ca.path
         intermediate = vault_mount.intermediate_ca.path
       }
     })
     filename = "${path.module}/vault-credentials.json"
   }
   ```

### Phase 11: Validation and Testing

1. **Test Certificate Generation**
   ```bash
   # Test Kubernetes certificate
   vault write pki-int/issue/kubernetes-svc \
     common_name="test.vault.svc.cluster.local"
   
   # Test device certificate
   vault write pki-int/issue/device-mtls \
     common_name="device-001.device.synadia.local"
   ```

2. **Verify Auto-unseal**
   ```bash
   # Restart a pod and verify it unseals automatically
   kubectl delete pod -n vault vault-0
   kubectl logs -n vault vault-0
   ```

## Best Practices

1. **Security**
   - Enable audit logging
   - Use least-privilege policies
   - Rotate root token
   - Enable MFA for sensitive operations

2. **Operations**
   - Regular backups of Vault data
   - Monitor certificate expiration
   - Automate certificate renewal
   - Use short-lived tokens

3. **PKI Management**
   - Keep root CA offline
   - Use intermediate CAs for signing
   - Implement certificate revocation
   - Monitor certificate usage

## Troubleshooting Guide

1. **Common Issues**
   - Seal/Unseal problems
   - Authentication failures
   - Certificate generation errors
   - Policy denials

2. **Debug Commands**
   ```bash
   # Check Vault status
   vault status
   
   # View audit logs
   kubectl logs -n vault vault-0
   
   # Test authentication
   vault auth list
   ```

## Outputs for Downstream Projects

- Vault endpoint URL
- CA certificate for TLS validation
- Authentication configuration
- PKI mount paths
- Policy names for reference