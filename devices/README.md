# Device Client

## Overview

This project provides a simple C client that connects to the NATS leaf cluster and simulates IoT device behavior. The client sends periodic metrics data and listens for instructions on a separate subject.

## Purpose

- Demonstrate device connectivity to NATS leaf cluster
- Send sample metrics data periodically
- Listen for and display received instructions
- Support mTLS authentication with device certificates
- Configurable device ID for multi-device simulation

## Dependencies

- NATS C client library
- OpenSSL for TLS support
- Device certificates from Vault
- Leaf cluster connection details

## Features

- mTLS connection to leaf cluster
- Configurable device ID
- Periodic metrics publishing:
  - Temperature readings
  - CPU usage
  - Memory usage
  - Network statistics
- Command listener on `device.<device_id>.cmd`
- Acknowledgment of received commands

## Building

```bash
make
```

## Usage

```bash
./device-client --device-id <device_id> \
                --cert <device_cert.pem> \
                --key <device_key.pem> \
                --ca <ca_cert.pem> \
                --server <leaf_cluster_url>
```

## Configuration

Environment variables:
- `DEVICE_ID`: Device identifier
- `NATS_URL`: Leaf cluster URL
- `CERT_PATH`: Path to device certificate
- `KEY_PATH`: Path to device private key
- `CA_PATH`: Path to CA certificate
- `METRICS_INTERVAL`: Seconds between metrics (default: 10)