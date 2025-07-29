# NATS Core Cluster Implementation

## Overview

This implementation deploys a NATS core cluster using the official NATS Helm chart, integrated with Synadia Control Plane (SCP) for operator mode configuration. The cluster is configured to accept leaf node connections and provides JetStream persistence.

## Architecture

```
┌─────────────────────┐
│  Synadia Control    │
│     Plane (SCP)     │
└──────────┬──────────┘
           │ Operator JWT +
           │ System Account
           ▼
┌─────────────────────┐
│   NATS Core Cluster │
│   (Operator Mode)   │
│                     │
│ ┌─────┐ ┌─────┐ ┌─────┐
│ │NATS-0│ │NATS-1│ │NATS-2│
│ └─────┘ └─────┘ └─────┘
│                     │
│    JetStream        │
│    Leaf Nodes       │
│    Monitoring       │
└─────────────────────┘
```

### Key Features

- **Operator Mode**: JWT-based authentication from SCP
- **High Availability**: 3-node cluster with automatic failover
- **JetStream**: Persistent streaming with 10Gi storage per node
- **Leaf Nodes**: Hub for edge cluster connections on port 7422
- **Monitoring**: Prometheus metrics and health endpoints

## Quick Start

```bash
# Initialize Terraform
make init

# Create NATS system in SCP and fetch configuration
make setup-system

# Deploy NATS cluster
make apply

# Test deployment
make test

# Get connection credentials
make get-credentials
```

## Implementation Details

### 1. SCP Integration

The `setup-nats-system.sh` script automates the creation of a NATS system in SCP:

1. Creates a dedicated team in SCP (default: "nats-team")
2. Creates a NATS system under that team (default: "nats-core")
3. Fetches the operator JWT and system account credentials
4. Saves configuration files locally:
   - `.operator-jwt`: Operator JWT for the NATS system
   - `.system-account`: System account credentials
   - `.resolver-preload`: Account resolver configuration

### 2. Helm Deployment

The NATS cluster is deployed using the official NATS Helm chart with custom values:

- **Operator Mode**: Configured with JWT from SCP
- **Clustering**: 3 replicas with anti-affinity rules
- **Storage**: Persistent volumes for JetStream data
- **Networking**: Exposed ports for clients, clustering, monitoring, and leaf nodes
- **Security**: TLS ready (certificates can be added via Vault integration)

Key configuration in `values.yaml.tpl`:

```yaml
config:
  cluster:
    enabled: true
    replicas: 3
    name: nats-core

  jetstream:
    enabled: true
    fileStore:
      enabled: true
      storageSize: 10Gi

  leafnodes:
    enabled: true
    port: 7422

  # Operator mode configuration from SCP
  operatorjwt: |
    ${OPERATOR_JWT}

  systemAccount: |
    ${SYSTEM_ACCOUNT}
```

### 3. Terraform Resources

The deployment creates:

1. **Kubernetes Namespace**: Dedicated namespace for NATS
2. **Operator Config Secret**: Contains JWT and system account credentials
3. **Helm Release**: NATS cluster deployment
4. **Service Monitor**: Optional Prometheus monitoring

### 4. Generated Files

After running `make setup-system`, the following files are created:

- `values.yaml`: Generated from template with SCP credentials
- `.operator-jwt`: JWT for operator mode authentication
- `.system-account`: System account credentials for admin access
- `.team-id` & `.system-id`: SCP resource identifiers

## Configuration Options

### Variables

Key variables in `variables.tf`:

- `nats_namespace`: Kubernetes namespace (default: "nats")
- `replicas`: Number of NATS nodes (default: 3)
- `enable_jetstream`: Enable JetStream (default: true)
- `jetstream_storage_size`: Storage per node (default: "10Gi")
- `enable_leafnodes`: Enable leaf node connections (default: true)
- `scp_system_name`: Name for NATS system in SCP (default: "nats-core")

### Ports

- **4222**: Client connections
- **6222**: Cluster routing
- **7422**: Leaf node connections
- **8222**: HTTP monitoring
- **7777**: Prometheus metrics

## Testing

The `test-nats.sh` script validates:

1. All pods are running and ready
2. NATS service is accessible
3. Client connections work (if `nats` CLI is installed)
4. Monitoring endpoints respond
5. JetStream is enabled (if configured)

## Outputs

The module provides:

- `nats_cluster_url`: Internal cluster connection URL
- `nats_external_url`: External connection URL (requires port-forward)
- `leafnode_url`: URL for leaf node connections
- `monitoring_url`: HTTP monitoring endpoint
- `port_forward_command`: Command to access NATS locally

## Troubleshooting

### Common Issues

1. **SCP Connection Failed**
   - Ensure SCP is deployed and accessible
   - Verify SCP credentials exist: `kubectl get secret scp-credentials -n scp`

2. **Operator JWT Not Found**
   - Run `make setup-system` to create NATS system in SCP
   - Check `.operator-jwt` file exists

3. **Pods Not Starting**
   - Check pod logs: `kubectl logs -n nats nats-0`
   - Verify storage class exists for JetStream PVCs

4. **Connection Refused**
   - Ensure port-forward is active: `make port-forward`
   - Check service endpoints: `kubectl get endpoints -n nats`

### Debug Commands

```bash
# View NATS logs
kubectl logs -n nats -l app.kubernetes.io/name=nats

# Check cluster formation
kubectl exec -n nats nats-0 -- nats-server --help

# Test from nats-box
kubectl exec -it -n nats deployment/nats-box -- sh
nats server list
```

## Next Steps

After deploying the NATS core cluster:

1. **Configure Accounts**: Create accounts in SCP for different applications
2. **Set Up Leaf Nodes**: Deploy edge NATS clusters that connect as leaf nodes
3. **Create Streams**: Configure JetStream streams for your use cases
4. **Enable Monitoring**: Connect Prometheus and Grafana for metrics
5. **Add TLS**: Configure certificates from Vault for secure connections

