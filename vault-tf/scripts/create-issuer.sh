#!/bin/bash
set -e

# Create service account and RBAC for cert-manager to use with Vault
kubectl apply -f - <<EOF
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-issuer
  namespace: cert-manager
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: cert-manager-vault-tokenreview
rules:
- apiGroups: [""]
  resources: ["serviceaccounts/token"]
  verbs: ["create"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: cert-manager-vault-tokenreview
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cert-manager-vault-tokenreview
subjects:
- kind: ServiceAccount
  name: cert-manager
  namespace: cert-manager
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: vault-issuer
spec:
  vault:
    server: http://vault.${VAULT_NAMESPACE}.svc.cluster.local:8200
    path: pki_int/sign/kubernetes
    auth:
      kubernetes:
        role: issuer
        mountPath: /v1/auth/kubernetes
        serviceAccountRef:
          name: vault-issuer
EOF