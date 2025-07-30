#!/bin/bash
set -e

# Test NATS Leaf Cluster Deployment

echo "=== Testing NATS Leaf Cluster ==="

# Get namespace from Terraform output
NAMESPACE=$(terraform output -raw namespace 2>/dev/null || echo "leaf-nats")
SERVICE_NAME=$(terraform output -raw service_name 2>/dev/null || echo "nats-leaf")

echo "Namespace: $NAMESPACE"
echo "Service: $SERVICE_NAME"
echo ""

# Check if namespace exists
if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
  echo "❌ Namespace $NAMESPACE not found"
  exit 1
fi
echo "✓ Namespace exists"

# Check pods
echo ""
echo "=== Checking Pods ==="
kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=nats

# Get pod status
READY_PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=nats -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' | grep -o "True" | wc -l || echo "0")
TOTAL_PODS=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=nats -o jsonpath='{.items[*].metadata.name}' | wc -w || echo "0")

if [ "$READY_PODS" -eq "$TOTAL_PODS" ] && [ "$TOTAL_PODS" -gt 0 ]; then
  echo "✓ All $READY_PODS pods are ready"
else
  echo "❌ Only $READY_PODS of $TOTAL_PODS pods are ready"
  echo ""
  echo "Pod details:"
  kubectl describe pods -n "$NAMESPACE" -l app.kubernetes.io/name=nats
  exit 1
fi

# Check service
echo ""
echo "=== Checking Service ==="
if kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
  echo "✓ Service $SERVICE_NAME exists"
  kubectl get svc "$SERVICE_NAME" -n "$NAMESPACE"
else
  echo "❌ Service $SERVICE_NAME not found"
  exit 1
fi

# Check leaf node connection
echo ""
echo "=== Checking Leaf Node Connection ==="
POD_NAME=$(kubectl get pods -n "$NAMESPACE" -l app.kubernetes.io/name=nats -o jsonpath='{.items[0].metadata.name}')
if [ -n "$POD_NAME" ]; then
  echo "Using pod: $POD_NAME"

  # Check NATS server info
  echo ""
  echo "Getting server info..."
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- wget -q -O - http://localhost:8222/varz | grep -E '"server_name"|"version"|"connections"|"leafnodes"' || echo "Unable to get server info"

  # Check leaf node connections
  echo ""
  echo "Checking leaf node connections..."
  kubectl exec -n "$NAMESPACE" "$POD_NAME" -- wget -q -O - http://localhost:8222/leafz | grep -E '"leaf_nodes"|"server_name"|"remote_url"' || echo "Unable to get leaf node info"
fi

echo ""
echo "=== Test Summary ==="
echo "✓ NATS leaf cluster is deployed"
echo "✓ Pods are running"
echo "✓ Service is available"
echo ""
echo "To check detailed leaf node status:"
echo "  kubectl port-forward -n $NAMESPACE svc/$SERVICE_NAME 8222:8222"
echo "  Then visit: http://localhost:8222/leafz"

