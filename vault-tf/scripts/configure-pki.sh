#!/bin/bash
set -e

echo "=== Configuring Vault PKI Backend ==="

# Validate environment variables
if [ -z "$ROOT_CA_PATH" ]; then
  echo "ERROR: ROOT_CA_PATH environment variable must be set"
  exit 1
fi

if [ ! -f "$ROOT_CA_PATH/root-ca.crt" ]; then
  echo "ERROR: Root CA certificate not found at $ROOT_CA_PATH/root-ca.crt"
  exit 1
fi

if [ ! -f "$ROOT_CA_PATH/root-ca.key" ]; then
  echo "ERROR: Root CA key not found at $ROOT_CA_PATH/root-ca.key"
  exit 1
fi

# Wait for Vault to be ready
echo "Waiting for Vault to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=vault -n $VAULT_NAMESPACE --timeout=60s

# Set up port forwarding
echo "Setting up port forwarding to Vault..."
kubectl port-forward -n $VAULT_NAMESPACE svc/vault 8200:8200 >/dev/null 2>&1 &
PF_PID=$!

# Give port forward time to establish
sleep 5

# Function to cleanup on exit
cleanup() {
  echo "Cleaning up..."
  if [ ! -z "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Check Vault is accessible
echo "Checking Vault connectivity..."
if ! curl -s -o /dev/null -w "%{http_code}" http://localhost:8200/v1/sys/health | grep -q "200"; then
  echo "ERROR: Cannot connect to Vault at http://localhost:8200"
  exit 1
fi

# Login to Vault
vault login -no-print $VAULT_TOKEN

# Enable PKI secrets engine
echo "Enabling PKI secrets engine..."
if vault secrets list | grep -q "pki_int/"; then
  echo "PKI secrets engine already enabled at pki_int/"
else
  vault secrets enable -path=pki_int pki
fi

# Configure PKI
vault secrets tune -max-lease-ttl=43800h pki_int

# Generate intermediate CSR
echo "Generating intermediate certificate signing request..."
vault write -format=json pki_int/intermediate/generate/internal \
  common_name="Demo Intermediate CA" \
  key_type="rsa" \
  key_bits="2048" \
  | jq -r '.data.csr' > ${TMPDIR:-/tmp}/intermediate.csr

# Sign intermediate certificate with external root CA
echo "Signing intermediate certificate with root CA..."
openssl x509 -req -in ${TMPDIR:-/tmp}/intermediate.csr \
  -CA "${ROOT_CA_PATH}/root-ca.crt" \
  -CAkey "${ROOT_CA_PATH}/root-ca.key" \
  -CAcreateserial \
  -out ${TMPDIR:-/tmp}/intermediate.crt \
  -days 1825 \
  -sha256 \
  -extfile <(cat <<EOF
basicConstraints=CA:TRUE,pathlen:0
keyUsage=digitalSignature,keyEncipherment,keyCertSign
EOF
)

# Create certificate bundle
echo "Creating certificate bundle..."
cat ${TMPDIR:-/tmp}/intermediate.crt "${ROOT_CA_PATH}/root-ca.crt" > ${TMPDIR:-/tmp}/intermediate-bundle.crt

# Import signed intermediate certificate
echo "Importing signed intermediate certificate..."
vault write pki_int/intermediate/set-signed \
  certificate=@${TMPDIR:-/tmp}/intermediate-bundle.crt

# Create certificate issuing role
echo "Creating certificate issuing role..."
vault write pki_int/roles/kubernetes \
  allowed_domains="cluster.local,svc.cluster.local,demo.local,localhost" \
  allow_subdomains=true \
  allow_bare_domains=true \
  allow_localhost=true \
  allow_ip_sans=true \
  server_flag=true \
  client_flag=true \
  max_ttl="720h" \
  ttl="24h"

# Configure Kubernetes authentication
echo "Configuring Kubernetes authentication..."

# Enable Kubernetes auth if not already enabled
if vault auth list | grep -q "kubernetes/"; then
  echo "Kubernetes auth already enabled"
else
  vault auth enable kubernetes
fi

# Configure Kubernetes auth from within the cluster
kubectl exec -n $VAULT_NAMESPACE vault-0 -- \
  vault write auth/kubernetes/config \
  kubernetes_host="https://kubernetes.default.svc:443"

# Create policy for certificate issuance
echo "Creating PKI issuer policy..."
vault policy write pki-issuer - <<EOF
path "pki_int/issue/kubernetes" {
  capabilities = ["create", "update"]
}
path "pki_int/sign/kubernetes" {
  capabilities = ["create", "update"]
}
EOF

# Create Kubernetes auth role
echo "Creating Kubernetes auth role..."
vault write auth/kubernetes/role/issuer \
  bound_service_account_names="vault-issuer,cert-manager,default" \
  bound_service_account_namespaces="cert-manager,default" \
  policies=pki-issuer \
  ttl=1h

# Test certificate generation
echo "Testing certificate generation..."
TEST_CERT=$(vault write -format=json pki_int/issue/kubernetes \
  common_name="test.demo.local" \
  ttl="1h" 2>/dev/null)

if [ $? -eq 0 ]; then
  echo "✓ Certificate generation test successful"
  echo "  Subject: $(echo "$TEST_CERT" | jq -r '.data.certificate' | openssl x509 -noout -subject)"
else
  echo "✗ Certificate generation test failed"
  exit 1
fi

# Clean up test files
rm -f ${TMPDIR:-/tmp}/intermediate.csr ${TMPDIR:-/tmp}/intermediate.crt ${TMPDIR:-/tmp}/intermediate-bundle.crt

echo "=== PKI configuration complete! ==="
echo ""
echo "Vault UI available at: http://localhost:30200"
echo "Token: $VAULT_TOKEN"
echo ""
echo "To manually request a certificate:"
echo "  vault write pki_int/issue/kubernetes common_name=myapp.demo.local"