#!/bin/bash
set -e

echo "=== Deploying NATS Leaf Cluster ==="

# Configuration
NAMESPACE="leaf-nats"
RELEASE_NAME="nats-leaf"
CHART_VERSION="1.2.2"
HELM_REPO="https://nats-io.github.io/k8s/helm/charts/"
LEAF_CREDS=".leaf.creds"

# Check prerequisites
if [ ! -f "$LEAF_CREDS" ]; then
    echo "ERROR: Leaf credentials not found at $LEAF_CREDS"
    echo "Please ensure .leaf.creds file exists in nats-leaf-tf directory."
    exit 1
fi

# Create namespace if it doesn't exist
kubectl get namespace $NAMESPACE >/dev/null 2>&1 || {
    echo "Creating namespace $NAMESPACE..."
    kubectl create namespace $NAMESPACE
}

# Create secret if it doesn't exist
kubectl get secret leaf-credentials -n $NAMESPACE >/dev/null 2>&1 || {
    echo "Creating leaf credentials secret..."
    kubectl create secret generic leaf-credentials \
        --from-file=leaf.creds=$LEAF_CREDS -n $NAMESPACE
}

# Add Helm repository
echo "Adding NATS Helm repository..."
helm repo add nats $HELM_REPO >/dev/null 2>&1 || true
helm repo update >/dev/null 2>&1

# Deploy using Helm
echo "Deploying NATS leaf cluster..."
helm upgrade --install $RELEASE_NAME nats/nats \
    --version $CHART_VERSION \
    --namespace $NAMESPACE \
    --values values.yaml \
    --wait \
    --timeout 10m

echo "✅ NATS Leaf cluster deployed successfully!"
echo ""
echo "Connection information:"
echo "  Namespace: $NAMESPACE"
echo "  Service: nats-leaf"
echo "  Client port: 4222"
echo "  Monitoring: 8222"
echo ""
echo "Test with: kubectl get pods -n $NAMESPACE"