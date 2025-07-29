#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Testing NATS Deployment ==="

# Check if namespace exists
NAMESPACE=$(terraform output -raw namespace 2>/dev/null || echo "nats")
if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
  echo "ERROR: NATS namespace not found"
  exit 1
fi

# Check pods
echo "Checking NATS pods..."
kubectl get pods -n $NAMESPACE

# Wait for all pods to be ready
echo ""
echo "Waiting for all NATS pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=nats -n $NAMESPACE --timeout=300s

# Check services
echo ""
echo "Checking NATS services..."
kubectl get svc -n $NAMESPACE

# Get service name
SERVICE_NAME=$(terraform output -raw service_name 2>/dev/null || echo "nats")

# Test NATS connection
echo ""
echo "Testing NATS connectivity..."

# Setup port forward
kubectl port-forward -n $NAMESPACE svc/$SERVICE_NAME 4222:4222 >/dev/null 2>&1 &
PF_PID=$!

cleanup() {
  if [ ! -z "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Wait for port forward
sleep 3

# Check if we have user credentials (not system account)
# System account credentials are not meant for client connections
if [ -f "$SCRIPT_DIR/../.user-creds" ] && [ -s "$SCRIPT_DIR/../.user-creds" ]; then
  export NATS_CREDS="$SCRIPT_DIR/../.user-creds"
  echo "Using user credentials for authentication"
fi

# Check if nats CLI is available
if command -v nats &>/dev/null; then
  echo "Testing with NATS CLI..."
  if [ ! -z "$NATS_CREDS" ]; then
    if nats --server nats://localhost:4222 --creds "$NATS_CREDS" server check connection; then
      echo "✓ NATS connection test successful with authentication"
    else
      echo "✗ NATS connection test failed"
      exit 1
    fi

    # Test server info
    echo ""
    echo "Getting server info..."
    nats --server nats://localhost:4222 --creds "$NATS_CREDS" server info || true
  else
    # Try without credentials (might fail with auth error)
    if nats --server nats://localhost:4222 server check connection 2>&1 | grep -q "Authorization Violation"; then
      echo "✓ NATS is running in operator mode (authorization required)"
    elif nats --server nats://localhost:4222 server check connection 2>&1 | grep -q "OK Connection OK"; then
      echo "✓ NATS connection test successful"
    else
      echo "✗ NATS connection test failed"
      exit 1
    fi
  fi
else
  echo "NATS CLI not found, testing with curl..."
  if curl -s http://localhost:8222/varz | grep -q server_id; then
    echo "✓ NATS monitoring endpoint accessible"
  else
    echo "✗ NATS monitoring endpoint test failed"
    exit 1
  fi
fi

# Check JetStream if enabled
if kubectl get statefulset -n $NAMESPACE $SERVICE_NAME 2>/dev/null | grep -q "3/3"; then
  echo ""
  echo "Checking JetStream status..."
  if command -v nats &>/dev/null; then
    nats --server nats://localhost:4222 server report jetstream || echo "JetStream info not available"
  fi
fi

# Check monitoring endpoint
echo ""
echo "Checking monitoring endpoint..."
# Set up port forward for monitoring
kubectl port-forward -n $NAMESPACE svc/$SERVICE_NAME 8222:8222 >/dev/null 2>&1 &
MON_PF_PID=$!
sleep 2

if curl -s http://localhost:8222/varz 2>/dev/null | grep -q "server_id"; then
  echo "✓ NATS monitoring endpoint accessible"

  # Check if operator mode is active
  SYSTEM_ACCOUNT=$(curl -s http://localhost:8222/varz 2>/dev/null | jq -r '.system_account // empty')
  if [ ! -z "$SYSTEM_ACCOUNT" ] && [ "$SYSTEM_ACCOUNT" != "null" ]; then
    echo "✓ NATS is running in operator mode with system account: $SYSTEM_ACCOUNT"
  fi
else
  echo "✗ NATS monitoring endpoint not accessible"
fi

# Clean up monitoring port forward
if [ ! -z "$MON_PF_PID" ]; then
  kill $MON_PF_PID 2>/dev/null || true
fi

echo ""
echo "=== NATS deployment test complete! ==="

