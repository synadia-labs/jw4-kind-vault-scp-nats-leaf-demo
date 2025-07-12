#!/bin/bash
set -e

echo "Creating test certificate..."

kubectl apply -f - <<EOF
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: vault-test-cert
  namespace: default
spec:
  secretName: vault-test-tls
  issuerRef:
    name: vault-issuer
    kind: ClusterIssuer
  commonName: test.demo.local
  dnsNames:
  - test.demo.local
  - test.svc.cluster.local
  duration: 24h
  renewBefore: 1h
EOF

echo "Waiting for certificate to be issued..."
sleep 5

echo ""
echo "=== Certificate Status ==="
kubectl get certificate vault-test-cert -n default

echo ""
echo "=== Certificate Details ==="
kubectl get secret vault-test-tls -n default -o jsonpath='{.data.tls\.crt}' | base64 -d | openssl x509 -text -noout | grep -E "(Subject:|Issuer:|Not Before:|Not After)"