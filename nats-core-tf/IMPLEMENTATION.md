# NATS Core Cluster Implementation Plan

## Architecture Overview

The NATS Core cluster serves as the central messaging hub, configured with Operator mode from SCP and auth callout for advanced authentication. This cluster will accept leaf node connections from edge clusters.

## Architecture Components

### 1. NATS Core Cluster
- **Deployment Type**: StatefulSet with persistent storage
- **Cluster Size**: 3-5 nodes for HA
- **Mode**: Operator mode with JWT authentication
- **Features**: JetStream, Auth Callout, Leaf Node hub

### 2. Authentication Architecture
- **Operator Mode**: JWT-based authentication
- **Auth Callout**: External authentication service
- **Account Isolation**: Multi-tenant account structure
- **Permission Model**: Subject-based ACLs

### 3. Networking Architecture
- **Client Port**: 4222 (TLS required)
- **Cluster Port**: 6222 (internal routing)
- **Monitoring Port**: 8222 (metrics/monitoring)
- **Leaf Node Port**: 7422 (leaf connections)

### 4. Storage Architecture
- **JetStream Storage**: File-based persistence
- **Storage Classes**: SSD for performance
- **Retention Policies**: Configurable per stream
- **Backup Strategy**: Snapshots and replication

## Implementation Steps

### Phase 1: Prerequisites

1. **Verify Dependencies**
   ```bash
   # Check SCP is running
   kubectl get pods -n scp
   
   # Verify SCP credentials
   scp system list
   
   # Check Vault access
   vault status
   
   # Create NATS namespace
   kubectl create namespace nats
   ```

2. **Retrieve SCP Configuration**
   ```bash
   # Get operator JWT
   scp system operator-jwt demo-nats > operator.jwt
   
   # Get system account
   scp system account demo-nats SYS > sys-account.jwt
   
   # Get resolver configuration
   scp system resolver-config demo-nats > resolver-preload.conf
   ```

### Phase 2: Terraform Configuration

1. **Directory Structure**
   ```
   nats-core-tf/
   ├── main.tf              # NATS deployment
   ├── variables.tf         # Input variables
   ├── outputs.tf          # Output values
   ├── helm.tf             # Helm deployment
   ├── config.tf           # NATS configuration
   ├── auth-callout.tf     # Auth service setup
   ├── certificates.tf     # TLS certificates
   ├── storage.tf          # JetStream storage
   ├── monitoring.tf       # Metrics and monitoring
   └── templates/
       ├── nats.conf       # NATS configuration template
       └── resolver.conf   # Resolver configuration
   ```

2. **Import SCP Credentials**
   ```hcl
   data "local_file" "scp_creds" {
     filename = "../scp-tf/scp-credentials.json"
   }
   
   locals {
     scp_config = jsondecode(data.local_file.scp_creds.content)
   }
   ```

### Phase 3: Certificate Configuration

1. **Request Certificates from Vault** (`certificates.tf`)
   ```hcl
   provider "vault" {
     address = var.vault_address
     token   = var.vault_token
   }
   
   resource "vault_pki_secret_backend_cert" "nats_server" {
     backend = "pki-int"
     name    = "nats-cluster"
     
     common_name = "*.nats.nats.svc.cluster.local"
     alt_names = [
       "nats.nats.svc.cluster.local",
       "*.nats.nats.svc",
       "nats-0.nats.nats.svc.cluster.local",
       "nats-1.nats.nats.svc.cluster.local",
       "nats-2.nats.nats.svc.cluster.local"
     ]
     
     ttl = "720h"
     auto_renew = true
   }
   ```

2. **Create Certificate Secrets**
   ```hcl
   resource "kubernetes_secret" "nats_certs" {
     metadata {
       name      = "nats-server-tls"
       namespace = "nats"
     }
     
     data = {
       "tls.crt" = vault_pki_secret_backend_cert.nats_server.certificate
       "tls.key" = vault_pki_secret_backend_cert.nats_server.private_key
       "ca.crt"  = vault_pki_secret_backend_cert.nats_server.ca_chain
     }
   }
   ```

### Phase 4: NATS Configuration

1. **Generate NATS Configuration** (`templates/nats.conf`)
   ```
   # Operator mode configuration
   operator: ${operator_jwt}
   system_account: ${system_account}
   
   # Resolver configuration
   resolver: {
     type: full
     dir: "/etc/nats-config/accounts/jwt"
   }
   
   # Server configuration
   server_name: $HOSTNAME
   
   # TLS Configuration
   tls: {
     cert_file: "/etc/nats-certs/tls.crt"
     key_file: "/etc/nats-certs/tls.key"
     ca_file: "/etc/nats-certs/ca.crt"
     verify_and_map: true
   }
   
   # Auth callout configuration
   authorization: {
     auth_callout: {
       issuer: "${auth_callout_issuer}"
       auth_users: [ "${auth_callout_jwt}" ]
       account: "${auth_callout_account}"
     }
   }
   
   # Cluster configuration
   cluster: {
     name: "nats-core"
     tls: {
       cert_file: "/etc/nats-certs/tls.crt"
       key_file: "/etc/nats-certs/tls.key"
       ca_file: "/etc/nats-certs/ca.crt"
     }
     routes: [
       nats://nats-0.nats:6222
       nats://nats-1.nats:6222
       nats://nats-2.nats:6222
     ]
   }
   
   # Leaf node configuration
   leafnodes: {
     port: 7422
     tls: {
       cert_file: "/etc/nats-certs/tls.crt"
       key_file: "/etc/nats-certs/tls.key"
       ca_file: "/etc/nats-certs/ca.crt"
       verify: true
     }
   }
   
   # JetStream configuration
   jetstream: {
     store_dir: "/data/jetstream"
     max_memory_store: 4Gi
     max_file_store: 100Gi
   }
   ```

2. **Create ConfigMap** (`config.tf`)
   ```hcl
   resource "kubernetes_config_map" "nats_config" {
     metadata {
       name      = "nats-config"
       namespace = "nats"
     }
     
     data = {
       "nats.conf" = templatefile("${path.module}/templates/nats.conf", {
         operator_jwt          = data.local_file.operator_jwt.content
         system_account       = data.local_file.system_account.content
         auth_callout_issuer  = var.auth_callout_issuer
         auth_callout_jwt     = var.auth_callout_jwt
         auth_callout_account = var.auth_callout_account
       })
       
       "resolver-preload.conf" = data.local_file.resolver_config.content
     }
   }
   ```

### Phase 5: Auth Callout Service

1. **Deploy Auth Service** (`auth-callout.tf`)
   ```hcl
   resource "kubernetes_deployment" "auth_callout" {
     metadata {
       name      = "nats-auth-callout"
       namespace = "nats"
     }
     
     spec {
       replicas = 3
       
       selector {
         match_labels = {
           app = "nats-auth-callout"
         }
       }
       
       template {
         metadata {
           labels = {
             app = "nats-auth-callout"
           }
         }
         
         spec {
           service_account_name = "nats-auth-callout"
           
           container {
             name  = "auth-service"
             image = "synadia/nats-auth-callout:latest"
             
             env {
               name  = "SCP_URL"
               value = local.scp_config.api_endpoint
             }
             
             env {
               name = "SCP_TOKEN"
               value_from {
                 secret_key_ref {
                   name = "scp-auth-token"
                   key  = "token"
                 }
               }
             }
             
             port {
               container_port = 9090
               name          = "http"
             }
           }
         }
       }
     }
   }
   ```

2. **Create Auth Service**
   ```hcl
   resource "kubernetes_service" "auth_callout" {
     metadata {
       name      = "nats-auth-callout"
       namespace = "nats"
     }
     
     spec {
       selector = {
         app = "nats-auth-callout"
       }
       
       port {
         port        = 9090
         target_port = 9090
         protocol    = "TCP"
       }
     }
   }
   ```

### Phase 6: NATS Deployment

1. **Helm Values Configuration**
   ```hcl
   locals {
     nats_values = {
       nats = {
         image = {
           repository = "nats"
           tag        = var.nats_version
         }
         
         jetstream = {
           enabled = true
           
           fileStorage = {
             enabled = true
             size    = "100Gi"
             storageClassName = var.storage_class
           }
           
           memoryStorage = {
             enabled = true
             size    = "4Gi"
           }
         }
       }
       
       cluster = {
         enabled = true
         replicas = 3
       }
       
       natsbox = {
         enabled = true
       }
       
       monitoring = {
         enabled = true
         service = {
           enabled = true
         }
       }
       
       auth = {
         enabled = false  # Using operator mode
       }
     }
   }
   ```

2. **Deploy NATS** (`helm.tf`)
   ```hcl
   resource "helm_release" "nats" {
     name       = "nats"
     namespace  = "nats"
     repository = "https://nats-io.github.io/k8s/helm/charts"
     chart      = "nats"
     version    = var.nats_helm_version
     
     values = [
       yamlencode(local.nats_values)
     ]
     
     set {
       name  = "nats.tls.secret.name"
       value = kubernetes_secret.nats_certs.metadata[0].name
     }
     
     set {
       name  = "config.nats"
       value = kubernetes_config_map.nats_config.data["nats.conf"]
     }
   }
   ```

### Phase 7: Storage Configuration

1. **JetStream Storage** (`storage.tf`)
   ```hcl
   resource "kubernetes_storage_class" "jetstream" {
     metadata {
       name = "jetstream-ssd"
     }
     
     storage_provisioner = "kubernetes.io/gce-pd"
     reclaim_policy     = "Retain"
     
     parameters = {
       type = "pd-ssd"
       replication-type = "regional-pd"
     }
   }
   ```

2. **Backup Configuration**
   ```hcl
   resource "kubernetes_cron_job" "jetstream_backup" {
     metadata {
       name      = "jetstream-backup"
       namespace = "nats"
     }
     
     spec {
       schedule = "0 2 * * *"  # Daily at 2 AM
       
       job_template {
         spec {
           template {
             spec {
               container {
                 name  = "backup"
                 image = "nats:alpine"
                 
                 command = [
                   "/bin/sh",
                   "-c",
                   "nats stream backup --server nats://nats:4222"
                 ]
               }
             }
           }
         }
       }
     }
   }
   ```

### Phase 8: Monitoring Setup

1. **ServiceMonitor for Prometheus** (`monitoring.tf`)
   ```hcl
   resource "kubernetes_manifest" "nats_servicemonitor" {
     manifest = {
       apiVersion = "monitoring.coreos.com/v1"
       kind       = "ServiceMonitor"
       
       metadata = {
         name      = "nats-metrics"
         namespace = "nats"
       }
       
       spec = {
         selector = {
           matchLabels = {
             app = "nats"
           }
         }
         
         endpoints = [{
           port     = "metrics"
           interval = "30s"
           path     = "/metrics"
         }]
       }
     }
   }
   ```

2. **Grafana Dashboard**
   ```hcl
   resource "kubernetes_config_map" "grafana_dashboard" {
     metadata {
       name      = "nats-dashboard"
       namespace = "monitoring"
       labels = {
         grafana_dashboard = "1"
       }
     }
     
     data = {
       "nats-dashboard.json" = file("${path.module}/dashboards/nats.json")
     }
   }
   ```

### Phase 9: Leaf Node Configuration

1. **Create Leaf Credentials**
   ```bash
   # Create account for leaf nodes
   scp account create --project demo-project \
     --name leaf-nodes \
     --description "Account for leaf node connections"
   
   # Create user for leaf authentication
   scp user create --account leaf-nodes \
     --name leaf-auth \
     --bearer-token
   ```

2. **Generate Leaf Configuration**
   ```hcl
   resource "local_file" "leaf_creds" {
     content = jsonencode({
       url      = "nats://nats.nats:7422"
       account  = var.leaf_account_jwt
       user     = var.leaf_user_jwt
       seed     = var.leaf_user_seed
       tls = {
         ca_file = "/etc/nats-certs/ca.crt"
       }
     })
     
     filename = "${path.module}/leaf-credentials.json"
   }
   ```

### Phase 10: Testing and Validation

1. **Connection Test**
   ```bash
   # Test from natsbox
   kubectl exec -it -n nats deployment/nats-box -- /bin/sh
   
   # Test basic connectivity
   nats-sub -s nats://nats:4222 "test.>"
   
   # Test auth
   nats context save core \
     --server nats://nats:4222 \
     --creds /etc/nats-creds/user.creds
   ```

2. **JetStream Test**
   ```bash
   # Create a stream
   nats stream add TEST \
     --subjects "test.*" \
     --storage file \
     --retention limits \
     --max-msgs=-1 \
     --max-bytes=-1 \
     --max-age=24h
   
   # Publish test messages
   nats pub test.data "Hello JetStream" --count=100
   ```

### Phase 11: Outputs Configuration

1. **Export Configuration** (`outputs.tf`)
   ```hcl
   output "nats_cluster_url" {
     value = "nats://nats.nats.svc.cluster.local:4222"
   }
   
   output "nats_leaf_url" {
     value = "nats://nats.nats.svc.cluster.local:7422"
   }
   
   output "operator_jwt" {
     value     = data.local_file.operator_jwt.content
     sensitive = true
   }
   
   output "system_account" {
     value     = data.local_file.system_account.content
     sensitive = true
   }
   
   output "leaf_credentials" {
     value     = local_file.leaf_creds.content
     sensitive = true
   }
   ```

## Best Practices

1. **Security**
   - Always use TLS
   - Rotate credentials regularly
   - Use operator mode for auth
   - Implement auth callout for advanced scenarios

2. **Performance**
   - Use SSD storage for JetStream
   - Configure appropriate memory limits
   - Monitor message rates
   - Tune OS parameters

3. **Reliability**
   - Deploy odd number of servers (3 or 5)
   - Use anti-affinity rules
   - Configure proper health checks
   - Implement backup strategy

## Troubleshooting Guide

1. **Common Issues**
   - JWT validation failures
   - TLS certificate problems
   - Cluster formation issues
   - JetStream storage problems

2. **Debug Commands**
   ```bash
   # Check cluster health
   nats server list
   
   # View server logs
   kubectl logs -n nats nats-0
   
   # Check JetStream status
   nats stream list
   
   # Monitor connections
   nats server report connections
   ```

## Outputs for Downstream Projects

- Core cluster URLs (client and leaf)
- Operator JWT for system management
- System account credentials
- Leaf node authentication details
- Monitoring endpoints