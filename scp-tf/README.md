# Synadia Control Plane (SCP)

## Overview

This project manages the installation and configuration of Synadia Control Plane (SCP) in the Kubernetes cluster. SCP will provide centralized management for NATS systems and generate configuration for downstream NATS deployments.

## Purpose

- Deploy Synadia Control Plane on Kubernetes
- Configure SCP with initial teams and projects
- Set up API access for programmatic management
- Integrate with Vault for certificate management

## Dependencies

- Kubernetes cluster (from k8s-tf project)
- Vault instance configured and ready (from vault-tf project)
- Terraform >= 1.0
- Helm >= 3.0
- SCP license

## Outputs

- `scp_credentials`: File containing SCP API credentials
- `scp_api_endpoint`: SCP API endpoint URL
- `scp_console_url`: SCP web console URL
- `team_id`: ID of the created team
- `project_id`: ID of the created project

## Usage

```bash
terraform init
terraform plan
terraform apply
```

## Configuration

Key components:
- SCP Helm chart deployment
- Initial team and project setup
- API token generation
- Integration with Vault for PKI
- Auth callout configuration