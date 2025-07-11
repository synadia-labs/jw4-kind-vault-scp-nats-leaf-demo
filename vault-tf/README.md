# Vault Infrastructure

## Overview

This project manages the installation and configuration of HashiCorp Vault in the Kubernetes cluster. Vault will be configured as a certificate issuer for Kubernetes and will provide tooling for issuing client certificates for mTLS devices.

## Purpose

- Deploy HashiCorp Vault on Kubernetes
- Configure Vault as a certificate issuer for the cluster
- Set up PKI backend for mTLS certificate generation
- Provide tooling for device certificate issuance

## Dependencies

- Kubernetes cluster (from k8s-tf project)
- Terraform >= 1.0
- Helm >= 3.0
- kubectl configured with cluster access

## Outputs

- `vault_credentials`: File containing Vault admin credentials
- `vault_endpoint`: Vault API endpoint
- `pki_mount_path`: Path to PKI backend for certificate issuance

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Configuration

Key components:
- Vault Helm chart deployment
- PKI backend configuration
- Kubernetes auth method
- Certificate issuance policies
- mTLS certificate templates