#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

echo "=== Testing System User with mTLS ==="

# Check if system user credentials exist
if [ ! -f "$ROOT_DIR/.sys-user.creds" ]; then
  echo "ERROR: System user credentials not found. Run 'make setup-sys-user' first."
  exit 1
fi

# Check if TLS certificates exist
if [ ! -f "$ROOT_DIR/.server-cert.pem" ] || [ ! -f "$ROOT_DIR/.server-key.pem" ] || [ ! -f "$ROOT_DIR/.ca-cert.pem" ]; then
  echo "ERROR: TLS certificates not found. Run 'make generate-tls' first."
  exit 1
fi

# Create a temporary directory for the test
TEST_DIR="$ROOT_DIR/.sys-user-test"
mkdir -p "$TEST_DIR"

# Copy credentials and certificates to test directory
cp "$ROOT_DIR/.sys-user.creds" "$TEST_DIR/sys-user.creds"
cp "$ROOT_DIR/.server-cert.pem" "$TEST_DIR/client-cert.pem"
cp "$ROOT_DIR/.server-key.pem" "$TEST_DIR/client-key.pem"
cp "$ROOT_DIR/.ca-cert.pem" "$TEST_DIR/ca.pem"

echo "Setting up port forward to NATS..."
kubectl port-forward -n nats svc/nats 4222:4222 >/dev/null 2>&1 &
PF_PID=$!

cleanup() {
  if [ ! -z "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
  fi
  rm -rf "$TEST_DIR"
}
trap cleanup EXIT

# Wait for port forward
sleep 3

echo ""
echo "Testing connection with mTLS..."

# Test with nats CLI using TLS options
if command -v nats >/dev/null 2>&1; then
  echo "Using nats CLI..."
  
  # Try connecting with TLS
  nats --server tls://localhost:4222 \
    --creds "$TEST_DIR/sys-user.creds" \
    --tlscert "$TEST_DIR/client-cert.pem" \
    --tlskey "$TEST_DIR/client-key.pem" \
    --tlsca "$TEST_DIR/ca.pem" \
    server check connection
  
  echo ""
  echo "✓ Successfully connected with system user over mTLS"
  
  # Try getting server info
  echo ""
  echo "Getting server info..."
  nats --server tls://localhost:4222 \
    --creds "$TEST_DIR/sys-user.creds" \
    --tlscert "$TEST_DIR/client-cert.pem" \
    --tlskey "$TEST_DIR/client-key.pem" \
    --tlsca "$TEST_DIR/ca.pem" \
    server report jetstream
else
  echo "NATS CLI not found. Please install it with:"
  echo "  brew install nats-io/nats-tools/nats"
  echo "  or"
  echo "  go install github.com/nats-io/natscli/nats@latest"
fi

echo ""
echo "=== Test Complete ===