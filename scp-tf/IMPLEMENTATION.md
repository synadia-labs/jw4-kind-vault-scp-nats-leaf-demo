# Synadia Control Plane Implementation Plan

## Architecture Overview

Synadia Control Plane (SCP) provides centralized management for NATS deployments. This implementation deploys SCP on Kubernetes, configures it for multi-tenant operation, and integrates with Vault for certificate management.

## Architecture Components

### 1. SCP Core Components
- **Control Plane Server**: Main SCP application
- **PostgreSQL Database**: Persistent storage for configuration
- **Redis Cache**: Session management and caching
- **MinIO/S3**: Object storage for artifacts

### 2. Multi-Tenancy Architecture
- **Teams**: Organizational units for isolation
- **Projects**: Logical groupings within teams
- **Systems**: NATS cluster configurations
- **Accounts**: NATS account management

### 3. Integration Points
- **Vault Integration**: Certificate generation and management
- **Kubernetes Integration**: Service discovery and deployment
- **NATS Integration**: Direct management of NATS clusters
- **Auth Integration**: OIDC/SAML support

### 4. API Architecture
- **REST API**: Primary management interface
- **GraphQL API**: Advanced querying capabilities
- **WebSocket**: Real-time updates
- **gRPC**: High-performance operations

## Implementation Steps

### Phase 1: Prerequisites

1. **Verify Dependencies**
   ```bash
   # Check Kubernetes cluster
   kubectl cluster-info
   kubectl get nodes
   
   # Verify Vault is running
   kubectl get pods -n vault
   
   # Create SCP namespace
   kubectl create namespace scp
   ```

2. **Obtain SCP License**
   - Contact Synadia for license key
   - Store license securely

3. **Storage Class Verification**
   ```bash
   # Check available storage classes
   kubectl get storageclass
   ```

### Phase 2: Terraform Configuration

1. **Directory Structure**
   ```
   scp-tf/
   ├── main.tf              # SCP deployment
   ├── variables.tf         # Input variables
   ├── outputs.tf          # Output values
   ├── helm.tf             # Helm deployment
   ├── database.tf         # PostgreSQL configuration
   ├── redis.tf            # Redis cache setup
   ├── storage.tf          # MinIO/S3 configuration
   ├── ingress.tf          # Ingress configuration
   ├── secrets.tf          # Secret management
   ├── teams.tf            # Team/project setup
   └── values/
       └── scp-values.yaml  # Helm values
   ```

2. **License Secret Creation**
   ```hcl
   resource "kubernetes_secret" "scp_license" {
     metadata {
       name      = "scp-license"
       namespace = "scp"
     }
     
     data = {
       "license.jwt" = var.scp_license
     }
   }
   ```

### Phase 3: Database Deployment

1. **PostgreSQL Setup** (`database.tf`)
   ```hcl
   resource "helm_release" "postgresql" {
     name       = "scp-postgresql"
     namespace  = "scp"
     repository = "https://charts.bitnami.com/bitnami"
     chart      = "postgresql"
     version    = var.postgresql_version
     
     values = [
       yamlencode({
         auth = {
           database = "scp"
           username = "scp"
           password = random_password.db_password.result
         }
         primary = {
           persistence = {
             size = "50Gi"
           }
         }
         metrics = {
           enabled = true
         }
       })
     ]
   }
   ```

2. **Database Migration Setup**
   - Automatic schema management
   - Backup configuration

### Phase 4: Cache Layer Deployment

1. **Redis Configuration** (`redis.tf`)
   ```hcl
   resource "helm_release" "redis" {
     name       = "scp-redis"
     namespace  = "scp"
     repository = "https://charts.bitnami.com/bitnami"
     chart      = "redis"
     version    = var.redis_version
     
     values = [
       yamlencode({
         auth = {
           enabled  = true
           password = random_password.redis_password.result
         }
         master = {
           persistence = {
             size = "10Gi"
           }
         }
         replica = {
           replicaCount = 2
         }
       })
     ]
   }
   ```

### Phase 5: Object Storage Setup

1. **MinIO Deployment** (`storage.tf`)
   ```hcl
   resource "helm_release" "minio" {
     name       = "scp-minio"
     namespace  = "scp"
     repository = "https://charts.min.io"
     chart      = "minio"
     version    = var.minio_version
     
     values = [
       yamlencode({
         mode = "distributed"
         replicas = 4
         persistence = {
           size = "100Gi"
         }
         buckets = [
           {
             name   = "scp-artifacts"
             policy = "none"
           }
         ]
       })
     ]
   }
   ```

### Phase 6: SCP Deployment

1. **Helm Values Configuration** (`values/scp-values.yaml`)
   ```yaml
   global:
     image:
       repository: synadia/control-plane
       tag: latest
   
   controlPlane:
     replicas: 3
     
     config:
       database:
         type: postgres
         host: scp-postgresql
         port: 5432
         name: scp
         user: scp
       
       cache:
         type: redis
         host: scp-redis-master
         port: 6379
       
       storage:
         type: s3
         endpoint: http://scp-minio:9000
         bucket: scp-artifacts
       
       vault:
         enabled: true
         address: https://vault.vault:8200
         auth:
           method: kubernetes
           role: scp
   
     license:
       secretName: scp-license
       key: license.jwt
   ```

2. **Deploy SCP** (`helm.tf`)
   ```hcl
   resource "helm_release" "scp" {
     name       = "scp"
     namespace  = "scp"
     repository = "https://charts.synadia.com"
     chart      = "control-plane"
     version    = var.scp_version
     
     values = [
       templatefile("${path.module}/values/scp-values.yaml", {
         db_password    = random_password.db_password.result
         redis_password = random_password.redis_password.result
         minio_access   = random_string.minio_access.result
         minio_secret   = random_password.minio_secret.result
         vault_token    = var.vault_token
       })
     ]
     
     depends_on = [
       helm_release.postgresql,
       helm_release.redis,
       helm_release.minio
     ]
   }
   ```

### Phase 7: Ingress Configuration

1. **Ingress Setup** (`ingress.tf`)
   ```hcl
   resource "kubernetes_ingress_v1" "scp" {
     metadata {
       name      = "scp-ingress"
       namespace = "scp"
       annotations = {
         "cert-manager.io/cluster-issuer" = "vault-issuer"
         "nginx.ingress.kubernetes.io/backend-protocol" = "HTTPS"
       }
     }
     
     spec {
       tls {
         hosts = [var.scp_domain]
         secret_name = "scp-tls"
       }
       
       rule {
         host = var.scp_domain
         http {
           path {
             path = "/"
             path_type = "Prefix"
             backend {
               service {
                 name = "scp"
                 port {
                   number = 443
                 }
               }
             }
           }
         }
       }
     }
   }
   ```

### Phase 8: Initial Configuration

1. **Bootstrap Admin User**
   ```bash
   # Get initial admin password
   kubectl get secret -n scp scp-admin-password \
     -o jsonpath='{.data.password}' | base64 -d
   
   # Login to SCP
   scp login --server https://${SCP_DOMAIN} \
     --user admin \
     --password <initial-password>
   ```

2. **Create API Token**
   ```bash
   # Generate long-lived API token
   scp token create --name terraform \
     --expiry 365d \
     --scope admin > scp-token.json
   ```

### Phase 9: Team and Project Setup

1. **Create Team via Terraform** (`teams.tf`)
   ```hcl
   resource "restapi_object" "team" {
     path = "/api/v1/teams"
     data = jsonencode({
       name        = "demo-team"
       description = "Demo team for Demo integration"
     })
     
     depends_on = [helm_release.scp]
   }
   
   resource "restapi_object" "project" {
     path = "/api/v1/teams/${restapi_object.team.id}/projects"
     data = jsonencode({
       name        = "demo-project"
       description = "Demo device management project"
     })
   }
   ```

2. **Create NATS System**
   ```hcl
   resource "restapi_object" "nats_system" {
     path = "/api/v1/projects/${restapi_object.project.id}/systems"
     data = jsonencode({
       name        = "demo-nats"
       description = "NATS system for Demo devices"
       config = {
         operator_mode = true
         auth_callout  = true
         leaf_nodes    = true
       }
     })
   }
   ```

### Phase 10: Vault Integration

1. **Configure Vault Auth for SCP**
   ```bash
   # Create policy for SCP
   vault policy write scp-policy - <<EOF
   path "pki-int/issue/nats-cluster" {
     capabilities = ["create", "update"]
   }
   path "pki-int/issue/scp-internal" {
     capabilities = ["create", "update"]
   }
   EOF
   
   # Create Kubernetes auth role
   vault write auth/kubernetes/role/scp \
     bound_service_account_names=scp \
     bound_service_account_namespaces=scp \
     policies=scp-policy \
     ttl=24h
   ```

2. **Enable Certificate Management**
   - Configure SCP to request certificates from Vault
   - Set up automatic renewal

### Phase 11: Auth Callout Configuration

1. **Deploy Auth Service**
   ```yaml
   apiVersion: apps/v1
   kind: Deployment
   metadata:
     name: nats-auth-service
     namespace: scp
   spec:
     replicas: 3
     template:
       spec:
         containers:
         - name: auth-service
           image: synadia/nats-auth-callout
           env:
           - name: SCP_URL
             value: https://scp:443
           - name: SCP_TOKEN
             valueFrom:
               secretKeyRef:
                 name: scp-auth-token
                 key: token
   ```

2. **Configure Auth Policies**
   - Device authentication rules
   - Subject permissions
   - Rate limiting

### Phase 12: Monitoring Setup

1. **Enable Metrics Export**
   ```yaml
   monitoring:
     prometheus:
       enabled: true
       port: 9090
     grafana:
       enabled: true
       dashboards:
         - scp-overview
         - nats-systems
         - auth-metrics
   ```

2. **Configure Alerts**
   - System health
   - License expiration
   - Resource usage

### Phase 13: Output Configuration

1. **Generate Outputs** (`outputs.tf`)
   ```hcl
   output "scp_credentials" {
     value = {
       api_endpoint = "https://${var.scp_domain}/api/v1"
       console_url  = "https://${var.scp_domain}"
       api_token    = var.scp_api_token
     }
     sensitive = true
   }
   
   output "team_id" {
     value = restapi_object.team.id
   }
   
   output "project_id" {
     value = restapi_object.project.id
   }
   
   output "system_config" {
     value = restapi_object.nats_system.api_response
   }
   ```

2. **Create Credentials File**
   ```hcl
   resource "local_file" "scp_creds" {
     content = jsonencode({
       api_endpoint = "https://${var.scp_domain}/api/v1"
       console_url  = "https://${var.scp_domain}"
       api_token    = var.scp_api_token
       team_id      = restapi_object.team.id
       project_id   = restapi_object.project.id
       system_id    = restapi_object.nats_system.id
     })
     filename = "${path.module}/scp-credentials.json"
   }
   ```

### Phase 14: Validation

1. **API Connectivity Test**
   ```bash
   # Test API access
   curl -H "Authorization: Bearer ${SCP_TOKEN}" \
     https://${SCP_DOMAIN}/api/v1/systems
   
   # Get system configuration
   scp system get demo-nats
   ```

2. **Generate NATS Configuration**
   ```bash
   # Export operator JWT
   scp system operator-jwt demo-nats > operator.jwt
   
   # Export system account
   scp system account demo-nats SYS > sys-account.jwt
   ```

## Best Practices

1. **Security**
   - Use strong passwords
   - Enable MFA for users
   - Rotate API tokens regularly
   - Implement RBAC

2. **High Availability**
   - Deploy multiple replicas
   - Use anti-affinity rules
   - Configure health checks
   - Implement backup strategy

3. **Operations**
   - Monitor resource usage
   - Set up alerting
   - Regular backups
   - Plan for upgrades

## Troubleshooting Guide

1. **Common Issues**
   - Database connection failures
   - License validation errors
   - Vault integration problems
   - API authentication issues

2. **Debug Commands**
   ```bash
   # Check SCP pods
   kubectl get pods -n scp
   
   # View SCP logs
   kubectl logs -n scp deployment/scp
   
   # Test database connectivity
   kubectl exec -n scp deployment/scp -- scp db test
   ```

## Outputs for Downstream Projects

- SCP API endpoint and credentials
- Team and Project IDs
- NATS system configuration
- Operator JWT and system account
- Auth callout service endpoint