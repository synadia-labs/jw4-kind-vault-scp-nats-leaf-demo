#!/usr/bin/env bash
set -euo pipefail

# Script to generate TLS certificates for NATS Leaf using Vault PKI

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VAULT_DIR="$(cd "$PROJECT_DIR/../vault-tf" && pwd)"

# Configuration
SERVICE_NAME="${SERVICE_NAME:-nats-leaf}"
NAMESPACE="${NAMESPACE:-leaf-nats}"
VAULT_NAMESPACE="${VAULT_NAMESPACE:-vault}"
CERT_TTL="${CERT_TTL:-8760h}" # 1 year

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if Vault is accessible
check_vault() {
  echo "Checking Vault connection..."

  # Check for vault token
  if [ ! -f "$VAULT_DIR/.vault-token" ]; then
    echo -e "${RED}ERROR: Vault token not found at $VAULT_DIR/.vault-token${NC}"
    echo "Please deploy Vault first: cd $VAULT_DIR && make apply"
    exit 1
  fi

  export VAULT_TOKEN=$(cat "$VAULT_DIR/.vault-token")
  export VAULT_ADDR="http://localhost:8200"

  # Port forward to Vault
  echo "Setting up port-forward to Vault..."
  kubectl port-forward -n "$VAULT_NAMESPACE" svc/vault 8200:8200 >/dev/null 2>&1 &
  PF_PID=$!
  trap "kill $PF_PID 2>/dev/null || true" EXIT

  # Wait for port forward
  sleep 3

  # Test vault connection
  if ! vault status >/dev/null 2>&1; then
    echo -e "${RED}ERROR: Cannot connect to Vault${NC}"
    exit 1
  fi

  echo -e "${GREEN}✓ Vault connection established${NC}"
}

# Generate server certificate for NATS Leaf
generate_server_cert() {
  echo "Generating server certificate for $SERVICE_NAME.$NAMESPACE.svc.cluster.local..."

  # Generate certificate with all pod-specific hostnames
  # Include individual pod names for StatefulSet
  POD_NAMES=""
  for i in 0 1 2; do
    POD_NAMES="${POD_NAMES}${SERVICE_NAME}-${i}.${SERVICE_NAME}-headless,"
    POD_NAMES="${POD_NAMES}${SERVICE_NAME}-${i}.${SERVICE_NAME}-headless.${NAMESPACE},"
    POD_NAMES="${POD_NAMES}${SERVICE_NAME}-${i}.${SERVICE_NAME}-headless.${NAMESPACE}.svc,"
    POD_NAMES="${POD_NAMES}${SERVICE_NAME}-${i}.${SERVICE_NAME}-headless.${NAMESPACE}.svc.cluster.local,"
  done

  CERT_RESPONSE=$(vault write -format=json pki_int/issue/kubernetes \
    common_name="$SERVICE_NAME.$NAMESPACE.svc.cluster.local" \
    alt_names="${POD_NAMES}$SERVICE_NAME.$NAMESPACE.svc.cluster.local,$SERVICE_NAME.$NAMESPACE.svc,$SERVICE_NAME.$NAMESPACE,$SERVICE_NAME,localhost,*.${SERVICE_NAME}.${NAMESPACE}.svc.cluster.local,*.${SERVICE_NAME}-headless.${NAMESPACE}.svc.cluster.local,${SERVICE_NAME}-headless,${SERVICE_NAME}-headless.${NAMESPACE},${SERVICE_NAME}-headless.${NAMESPACE}.svc,${SERVICE_NAME}-headless.${NAMESPACE}.svc.cluster.local" \
    ip_sans="127.0.0.1" \
    ttl="$CERT_TTL")

  # Extract certificate components
  echo "$CERT_RESPONSE" | jq -r '.data.certificate' >"$PROJECT_DIR/.server-cert.pem"
  echo "$CERT_RESPONSE" | jq -r '.data.private_key' >"$PROJECT_DIR/.server-key.pem"
  echo "$CERT_RESPONSE" | jq -r '.data.ca_chain[]' >"$PROJECT_DIR/.ca-cert.pem"

  # Set proper permissions
  chmod 600 "$PROJECT_DIR/.server-cert.pem"
  chmod 600 "$PROJECT_DIR/.server-key.pem"
  chmod 600 "$PROJECT_DIR/.ca-cert.pem"

  echo -e "${GREEN}✓ Server certificate generated${NC}"
}

# Main execution
main() {
  echo "=== NATS Leaf TLS Certificate Generation ==="
  echo ""

  # Also copy CA from core if it exists
  if [ -f "$PROJECT_DIR/../nats-core-tf/.ca-cert.pem" ]; then
    echo "Using CA certificate from nats-core-tf..."
    cp "$PROJECT_DIR/../nats-core-tf/.ca-cert.pem" "$PROJECT_DIR/.ca-cert.pem"
    chmod 600 "$PROJECT_DIR/.ca-cert.pem"
  else
    check_vault
  fi

  check_vault
  generate_server_cert

  echo ""
  echo -e "${GREEN}=== TLS Certificate Generation Complete ===${NC}"
  echo ""
  echo "Generated files:"
  echo "  - .server-cert.pem (server certificate)"
  echo "  - .server-key.pem (server private key)"
  echo "  - .ca-cert.pem (CA certificate)"
  echo ""
  echo "The Kubernetes secret will be created by Terraform during deployment"
}

main "$@"
