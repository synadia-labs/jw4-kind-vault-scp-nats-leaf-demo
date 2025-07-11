# NATS Leaf Node Cluster

## Overview

This project provisions a NATS leaf node cluster that connects to the core NATS cluster. Devices connect to this leaf cluster using mTLS and potentially auth callout for authentication.

## Purpose

- Deploy NATS leaf node cluster on Kubernetes
- Configure leaf node connection to core cluster
- Enable mTLS for device connections
- Set up auth callout for device authentication
- Provide edge connectivity for IoT devices

## Dependencies

- Kubernetes cluster (from k8s-tf project)
- Vault instance for certificates (from vault-tf project)
- NATS core cluster running (from nats-core-tf project)
- Leaf node credentials from core cluster
- Terraform >= 1.0
- Helm >= 3.0

## Outputs

- `leaf_cluster_url`: Leaf cluster connection URL for devices
- `mtls_ca_cert`: CA certificate for device mTLS
- `device_subjects`: Available subjects for device communication

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Configuration

Key components:
- NATS Helm chart deployment (leaf configuration)
- Leaf node connection to core cluster
- mTLS configuration for device connections
- Auth callout service for device authentication
- Subject mapping and permissions
- Device connection limits and policies