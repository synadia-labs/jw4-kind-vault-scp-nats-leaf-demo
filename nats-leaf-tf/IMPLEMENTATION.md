# NATS Leaf Node Cluster Implementation Plan

## Architecture Overview

The NATS Leaf Node cluster provides edge connectivity for IoT devices. It connects to the core NATS cluster as a leaf node while accepting device connections via mTLS and optional auth callout.

## Architecture Components

### 1. Leaf Node Cluster
- **Deployment Type**: StatefulSet for stability
- **Cluster Size**: 3 nodes for local HA
- **Connection Mode**: Leaf node to core cluster
- **Device Interface**: mTLS with certificate validation

### 2. Device Connection Architecture
- **mTLS**: Certificate-based device authentication
- **Auth Callout**: Optional additional authentication
- **Connection Limits**: Per-device connection management
- **Subject Mapping**: Device to core subject translation

### 3. Networking Architecture
- **Device Port**: 4222 (mTLS required)
- **Cluster Port**: 6222 (internal only)
- **Monitoring Port**: 8222 (metrics)
- **Leaf Connection**: Outbound to core cluster

### 4. Security Architecture
- **Device Certificates**: Vault-issued per device
- **Certificate Validation**: CN-based device identification
- **Subject Isolation**: Device-specific namespaces
- **Rate Limiting**: Per-device message limits

## Implementation Steps

### Phase 1: Prerequisites

1. **Verify Dependencies**
   ```bash
   # Check core NATS cluster
   kubectl get pods -n nats
   
   # Verify leaf credentials from core
   cat ../nats-core-tf/leaf-credentials.json
   
   # Check Vault access for device certs
   vault status
   
   # Create leaf namespace
   kubectl create namespace nats-leaf
   ```

2. **Import Core Configuration**
   ```bash
   # Get leaf credentials from core deployment
   cd ../nats-core-tf
   terraform output -json leaf_credentials > ../nats-leaf-tf/leaf-creds.json
   cd ../nats-leaf-tf
   ```

### Phase 2: Terraform Configuration

1. **Directory Structure**
   ```
   nats-leaf-tf/
   ├── main.tf              # Leaf cluster deployment
   ├── variables.tf         # Input variables
   ├── outputs.tf          # Output values
   ├── helm.tf             # Helm deployment
   ├── config.tf           # Leaf configuration
   ├── certificates.tf     # TLS certificates
   ├── device-auth.tf      # Device authentication
   ├── monitoring.tf       # Metrics setup
   └── templates/
       ├── leaf.conf       # Leaf node configuration
       └── device-auth.lua # Auth callout script
   ```

2. **Import Dependencies**
   ```hcl
   # Import core cluster credentials
   data "local_file" "leaf_creds" {
     filename = "${path.module}/leaf-creds.json"
   }
   
   locals {
     leaf_config = jsondecode(data.local_file.leaf_creds.content)
   }
   
   # Import Vault configuration
   data "local_file" "vault_creds" {
     filename = "../vault-tf/vault-credentials.json"
   }
   
   locals {
     vault_config = jsondecode(data.local_file.vault_creds.content)
   }
   ```

### Phase 3: Certificate Configuration

1. **Leaf Node Certificates** (`certificates.tf`)
   ```hcl
   # Leaf node server certificates
   resource "vault_pki_secret_backend_cert" "leaf_server" {
     backend = "pki-int"
     name    = "nats-cluster"
     
     common_name = "*.nats-leaf.nats-leaf.svc.cluster.local"
     alt_names = [
       "nats-leaf.nats-leaf.svc.cluster.local",
       "*.nats-leaf.nats-leaf.svc",
       "nats-leaf-0.nats-leaf.nats-leaf.svc.cluster.local",
       "nats-leaf-1.nats-leaf.nats-leaf.svc.cluster.local",
       "nats-leaf-2.nats-leaf.nats-leaf.svc.cluster.local"
     ]
     
     ttl = "720h"
     auto_renew = true
   }
   
   # Device CA certificate for validation
   data "vault_generic_secret" "device_ca" {
     path = "pki-int/cert/ca"
   }
   ```

2. **Create Certificate Secrets**
   ```hcl
   resource "kubernetes_secret" "leaf_certs" {
     metadata {
       name      = "nats-leaf-tls"
       namespace = "nats-leaf"
     }
     
     data = {
       "tls.crt" = vault_pki_secret_backend_cert.leaf_server.certificate
       "tls.key" = vault_pki_secret_backend_cert.leaf_server.private_key
       "ca.crt"  = vault_pki_secret_backend_cert.leaf_server.ca_chain
       "device-ca.crt" = data.vault_generic_secret.device_ca.data["certificate"]
     }
   }
   ```

### Phase 4: Leaf Node Configuration

1. **Leaf Configuration Template** (`templates/leaf.conf`)
   ```
   # Server identification
   server_name: $HOSTNAME
   
   # Leaf node configuration
   leafnodes {
     remotes = [
       {
         url: "${core_url}"
         account: "${leaf_account}"
         credentials: "/etc/nats-creds/leaf.creds"
         tls: {
           ca_file: "/etc/nats-certs/ca.crt"
           cert_file: "/etc/nats-certs/tls.crt"
           key_file: "/etc/nats-certs/tls.key"
         }
       }
     ]
   }
   
   # Device connection configuration
   port: 4222
   
   tls: {
     cert_file: "/etc/nats-certs/tls.crt"
     key_file: "/etc/nats-certs/tls.key"
     ca_file: "/etc/nats-certs/device-ca.crt"
     verify: true
     verify_cert_and_check_known_urls: true
   }
   
   # Auth callout for device authentication
   authorization: {
     auth_callout: {
       issuer: "${auth_callout_issuer}"
       auth_users: [ "${auth_callout_jwt}" ]
       account: "${device_account}"
     }
   }
   
   # Cluster configuration
   cluster {
     name: "nats-leaf"
     port: 6222
     
     tls: {
       cert_file: "/etc/nats-certs/tls.crt"
       key_file: "/etc/nats-certs/tls.key"
       ca_file: "/etc/nats-certs/ca.crt"
     }
     
     routes = [
       nats://nats-leaf-0.nats-leaf:6222
       nats://nats-leaf-1.nats-leaf:6222
       nats://nats-leaf-2.nats-leaf:6222
     ]
   }
   
   # Monitoring
   http: 8222
   
   # Limits for device connections
   max_connections: 10000
   max_control_line: 4096
   max_payload: 1048576  # 1MB
   
   # Write deadline for slow consumers
   write_deadline: "10s"
   ```

2. **Create ConfigMaps** (`config.tf`)
   ```hcl
   resource "kubernetes_config_map" "leaf_config" {
     metadata {
       name      = "nats-leaf-config"
       namespace = "nats-leaf"
     }
     
     data = {
       "leaf.conf" = templatefile("${path.module}/templates/leaf.conf", {
         core_url             = local.leaf_config.url
         leaf_account        = local.leaf_config.account
         auth_callout_issuer = var.auth_callout_issuer
         auth_callout_jwt    = var.auth_callout_jwt
         device_account      = var.device_account
       })
     }
   }
   
   resource "kubernetes_secret" "leaf_creds" {
     metadata {
       name      = "nats-leaf-creds"
       namespace = "nats-leaf"
     }
     
     data = {
       "leaf.creds" = base64encode(local.leaf_config.creds)
     }
   }
   ```

### Phase 5: Device Authentication Setup

1. **Auth Callout Service** (`device-auth.tf`)
   ```hcl
   resource "kubernetes_deployment" "device_auth" {
     metadata {
       name      = "device-auth-callout"
       namespace = "nats-leaf"
     }
     
     spec {
       replicas = 2
       
       selector {
         match_labels = {
           app = "device-auth"
         }
       }
       
       template {
         metadata {
           labels = {
             app = "device-auth"
           }
         }
         
         spec {
           container {
             name  = "auth-service"
             image = "synadia/device-auth-callout:latest"
             
             env {
               name  = "VAULT_ADDR"
               value = local.vault_config.vault_addr
             }
             
             env {
               name = "VAULT_TOKEN"
               value_from {
                 secret_key_ref {
                   name = "vault-token"
                   key  = "token"
                 }
               }
             }
             
             env {
               name  = "DEVICE_SUBJECT_PREFIX"
               value = "device"
             }
             
             port {
               container_port = 9090
               name          = "http"
             }
             
             liveness_probe {
               http_get {
                 path = "/health"
                 port = 9090
               }
               initial_delay_seconds = 10
               period_seconds        = 30
             }
           }
         }
       }
     }
   }
   ```

2. **Device Authentication Logic**
   ```lua
   -- templates/device-auth.lua
   -- Extract device ID from certificate CN
   function authenticate(cert_cn, client_info)
     -- Expected format: device-XXXX.device.synadia.local
     local device_id = string.match(cert_cn, "device%-(%w+)")
     
     if not device_id then
       return { error = "Invalid device certificate" }
     end
     
     -- Check device registration in Vault
     local device_info = vault_lookup(device_id)
     if not device_info then
       return { error = "Device not registered" }
     end
     
     -- Return permissions
     return {
       sub = {
         -- Device can publish to its own topics
         "device." .. device_id .. ".>",
         -- Device can subscribe to commands
         "_INBOX.>",
         "device." .. device_id .. ".cmd"
       },
       pub = {
         -- Device can publish metrics
         "device." .. device_id .. ".metrics.>",
         -- Device can publish status
         "device." .. device_id .. ".status",
         -- Response to commands
         "_INBOX.>"
       },
       -- Connection limits
       data = 1048576,  -- 1MB/s
       subs = 100,      -- Max subscriptions
       payload = 65536  -- 64KB max message
     }
   end
   ```

### Phase 6: Helm Deployment

1. **Helm Values Configuration**
   ```hcl
   locals {
     leaf_values = {
       nats = {
         image = {
           repository = "nats"
           tag        = var.nats_version
         }
         
         jetstream = {
           enabled = false  # Leaf nodes don't need JetStream
         }
       }
       
       cluster = {
         enabled = true
         replicas = 3
       }
       
       leafnodes = {
         enabled = true
         noAdvertise = false
       }
       
       config = {
         cluster = {
           port = 6222
         }
         leafnodes = {
           port = 7422
         }
       }
       
       podTemplate = {
         topologySpreadConstraints = [
           {
             maxSkew = 1
             topologyKey = "topology.kubernetes.io/zone"
             whenUnsatisfiable = "DoNotSchedule"
             labelSelector = {
               matchLabels = {
                 app = "nats-leaf"
               }
             }
           }
         ]
       }
     }
   }
   ```

2. **Deploy Leaf Cluster** (`helm.tf`)
   ```hcl
   resource "helm_release" "nats_leaf" {
     name       = "nats-leaf"
     namespace  = "nats-leaf"
     repository = "https://nats-io.github.io/k8s/helm/charts"
     chart      = "nats"
     version    = var.nats_helm_version
     
     values = [
       yamlencode(local.leaf_values)
     ]
     
     set {
       name  = "config.nats"
       value = kubernetes_config_map.leaf_config.data["leaf.conf"]
     }
     
     set {
       name  = "nats.tls.secret.name"
       value = kubernetes_secret.leaf_certs.metadata[0].name
     }
   }
   ```

### Phase 7: External Access Configuration

1. **LoadBalancer Service**
   ```hcl
   resource "kubernetes_service" "leaf_external" {
     metadata {
       name      = "nats-leaf-external"
       namespace = "nats-leaf"
       annotations = {
         "cloud.google.com/load-balancer-type" = "Internal"
       }
     }
     
     spec {
       type = "LoadBalancer"
       
       selector = {
         app = "nats-leaf"
       }
       
       port {
         name        = "client"
         port        = 4222
         target_port = 4222
         protocol    = "TCP"
       }
     }
   }
   ```

2. **DNS Configuration**
   ```hcl
   resource "google_dns_record_set" "leaf_cluster" {
     name = "leaf-nats.${var.domain}."
     type = "A"
     ttl  = 300
     
     managed_zone = var.dns_zone
     rrdatas = [kubernetes_service.leaf_external.status[0].load_balancer[0].ingress[0].ip]
   }
   ```

### Phase 8: Monitoring Configuration

1. **Prometheus Metrics** (`monitoring.tf`)
   ```hcl
   resource "kubernetes_service" "leaf_metrics" {
     metadata {
       name      = "nats-leaf-metrics"
       namespace = "nats-leaf"
       labels = {
         app = "nats-leaf"
         metrics = "prometheus"
       }
     }
     
     spec {
       selector = {
         app = "nats-leaf"
       }
       
       port {
         name        = "metrics"
         port        = 7777
         target_port = 7777
       }
     }
   }
   
   resource "kubernetes_manifest" "leaf_servicemonitor" {
     manifest = {
       apiVersion = "monitoring.coreos.com/v1"
       kind       = "ServiceMonitor"
       
       metadata = {
         name      = "nats-leaf-metrics"
         namespace = "nats-leaf"
       }
       
       spec = {
         selector = {
           matchLabels = {
             app = "nats-leaf"
             metrics = "prometheus"
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

### Phase 9: Device Certificate Management

1. **Device Registration Script**
   ```bash
   #!/bin/bash
   # scripts/register-device.sh
   
   DEVICE_ID=$1
   VAULT_ADDR=$2
   VAULT_TOKEN=$3
   
   # Generate device certificate
   vault write pki-int/issue/device-mtls \
     common_name="device-${DEVICE_ID}.device.synadia.local" \
     ttl="168h" \
     format="pem" > device-${DEVICE_ID}.json
   
   # Extract certificate and key
   jq -r '.data.certificate' device-${DEVICE_ID}.json > device-${DEVICE_ID}.crt
   jq -r '.data.private_key' device-${DEVICE_ID}.json > device-${DEVICE_ID}.key
   jq -r '.data.ca_chain' device-${DEVICE_ID}.json > device-ca-chain.crt
   
   # Store device metadata in Vault
   vault kv put secret/devices/${DEVICE_ID} \
     registered_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     status="active" \
     device_type="iot-sensor"
   ```

2. **Terraform Device Management**
   ```hcl
   resource "null_resource" "register_test_devices" {
     count = var.test_device_count
     
     provisioner "local-exec" {
       command = "${path.module}/scripts/register-device.sh device-${format("%04d", count.index + 1)} ${local.vault_config.vault_addr} ${var.vault_token}"
     }
   }
   ```

### Phase 10: Testing and Validation

1. **Test Device Connection**
   ```bash
   # Test with device certificate
   nats-cli --tlscert=device-0001.crt \
            --tlskey=device-0001.key \
            --tlsca=device-ca-chain.crt \
            --server=tls://leaf-nats.example.com:4222 \
            pub device.0001.status "online"
   ```

2. **Verify Leaf Connection**
   ```bash
   # Check leaf node status from core
   kubectl exec -it -n nats nats-0 -- nats server list
   
   # Should see leaf nodes connected
   kubectl exec -it -n nats nats-0 -- nats server report connections
   ```

### Phase 11: Output Configuration

1. **Export Configuration** (`outputs.tf`)
   ```hcl
   output "leaf_cluster_url" {
     value = "tls://${kubernetes_service.leaf_external.status[0].load_balancer[0].ingress[0].ip}:4222"
   }
   
   output "leaf_cluster_dns" {
     value = "tls://leaf-nats.${var.domain}:4222"
   }
   
   output "mtls_ca_cert" {
     value = data.vault_generic_secret.device_ca.data["certificate"]
   }
   
   output "device_subjects" {
     value = {
       metrics  = "device.*.metrics.>"
       status   = "device.*.status"
       commands = "device.*.cmd"
     }
   }
   
   output "device_registration_script" {
     value = "${path.module}/scripts/register-device.sh"
   }
   ```

## Best Practices

1. **Security**
   - Enforce mTLS for all device connections
   - Validate device certificates
   - Implement subject isolation
   - Regular certificate rotation

2. **Performance**
   - Tune connection limits
   - Implement message rate limiting
   - Monitor leaf connection health
   - Use regional deployment

3. **Operations**
   - Monitor certificate expiration
   - Track device connections
   - Alert on leaf disconnection
   - Regular security audits

## Troubleshooting Guide

1. **Common Issues**
   - Device certificate validation failures
   - Leaf connection to core problems
   - Auth callout failures
   - Subject permission denials

2. **Debug Commands**
   ```bash
   # Check leaf status
   kubectl logs -n nats-leaf nats-leaf-0
   
   # Verify leaf connection from core
   kubectl exec -n nats nats-0 -- nats server leafz
   
   # Test device certificate
   openssl x509 -in device-0001.crt -text -noout
   
   # Monitor connections
   kubectl exec -n nats-leaf nats-leaf-0 -- nats server connections
   ```

## Outputs for Downstream Projects

- Leaf cluster connection URL
- Device CA certificate
- Device subject patterns
- Registration scripts
- Monitoring endpoints