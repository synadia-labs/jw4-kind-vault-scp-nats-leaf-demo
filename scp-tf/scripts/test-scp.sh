#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "=== Testing SCP Deployment ==="

# Check if namespace exists
if ! kubectl get namespace scp >/dev/null 2>&1; then
  echo "ERROR: SCP namespace not found"
  exit 1
fi

# Check pods
echo "Checking SCP pods..."
kubectl get pods -n scp

# Check service
echo ""
echo "Checking SCP service..."
kubectl get svc -n scp

# Test API if token exists
if [ -f "$SCRIPT_DIR/../.api-token" ]; then
  echo ""
  echo "Testing API connectivity..."

  TOKEN=$(cat "$SCRIPT_DIR/../.api-token")

  # Set up port forward
  kubectl port-forward -n scp svc/scp-control-plane 8080:8080 >/dev/null 2>&1 &
  PF_PID=$!

  # Cleanup function
  cleanup() {
    if [ ! -z "$PF_PID" ]; then
      kill $PF_PID 2>/dev/null || true
    fi
  }
  trap cleanup EXIT

  # Wait for port forward
  sleep 3

  # Test API - try different endpoints
  API_TESTED=false
  for ENDPOINT in "/api/core/beta/teams" "/api/core/beta/authz/roles"; do
    if curl -s -H "Authorization: Bearer $TOKEN" "http://localhost:8080$ENDPOINT" | grep -q '\[' 2>/dev/null; then
      echo "✓ API test successful (endpoint: $ENDPOINT)"
      API_TESTED=true
      break
    fi
  done

  if [ "$API_TESTED" != "true" ]; then
    echo "✗ API test failed"
    exit 1
  fi
else
  echo ""
  echo "Skipping API test - no token found"
fi

echo ""
echo "=== SCP deployment test complete! ==="