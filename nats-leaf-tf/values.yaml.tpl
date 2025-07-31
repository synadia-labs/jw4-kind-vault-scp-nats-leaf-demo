# NATS Leaf Helm Values
# Generated from template - DO NOT EDIT DIRECTLY

# Common CA for all TLS connections
tlsCA:
  enabled: true
  secretName: nats-leaf-tls
  key: ca.crt

config:
  cluster:
    enabled: true
    replicas: 3
    name: nats-leaf
    tls:
      enabled: true
      secretName: nats-leaf-tls
  
  jetstream:
    enabled: true
    fileStore:
      enabled: true
      storageDirectory: /data/jetstream
      pvc:
        enabled: true
        size: 10Gi
        storageClassName: standard
    memoryStore:
      enabled: true
      maxSize: 1Gi
  
  leafnodes:
    enabled: false
    noAdvertise: true
    port: 7422
  
  monitor:
    enabled: true
    port: 8222
  
  resolver:
    enabled: true
    merge:
      type: full
      interval: 2m
      timeout: 1.9s
  
  merge:
    operator: |
${OPERATOR_JWT}
    system_account: ${SYSTEM_ACCOUNT_ID}
    resolver_preload:
${RESOLVER_PRELOAD}
    leafnodes:
      remotes:
      - account: "${LEAF_ACCOUNT_ID}"
        credentials: "/etc/nats-creds/leaf.creds"
        urls:
        - "tls://nats.nats.svc.cluster.local:7422"
        tls:
          ca_file: "/etc/nats-ca-cert/ca.crt"
      - account: "${SYSTEM_ACCOUNT_ID}"
        credentials: "/etc/nats-creds/sys-user.creds"
        urls:
        - "tls://nats.nats.svc.cluster.local:7422"
        tls:
          ca_file: "/etc/nats-ca-cert/ca.crt"

configMap:
  name: nats-leaf-config

service:
  name: nats-leaf
  ports:
    nats:
      port: 4222
    monitor:
      enabled: true
      port: 8222

headlessService:
  name: nats-leaf-headless

promExporter:
  enabled: true
  port: 7777
  image:
    repository: natsio/prometheus-nats-exporter
    tag: latest
    pullPolicy: IfNotPresent

natsBox:
  enabled: true

podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

statefulSet:
  name: nats-leaf

podTemplate:
  configChecksumAnnotation: true
  patch:
  - op: add
    path: /spec/volumes/-
    value:
      name: leaf-creds
      secret:
        secretName: leaf-credentials
  - op: add
    path: /spec/volumes/-
    value:
      name: operator-config
      secret:
        secretName: nats-operator-config
  - op: add
    path: /spec/volumes/-
    value:
      name: nats-ca
      secret:
        secretName: nats-leaf-tls
        items:
        - key: ca.crt
          path: ca.crt
  - op: add
    path: /spec/containers/0/volumeMounts/-
    value:
      name: leaf-creds
      mountPath: /etc/nats-creds
      readOnly: true
  - op: add
    path: /spec/containers/0/volumeMounts/-
    value:
      name: operator-config
      mountPath: /etc/nats-operator
      readOnly: true
  - op: add
    path: /spec/containers/0/volumeMounts/-
    value:
      name: nats-ca
      mountPath: /etc/nats-ca
      readOnly: true
