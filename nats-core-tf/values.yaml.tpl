# NATS Core Helm Values
# Generated from template - DO NOT EDIT DIRECTLY

# Common CA for all TLS connections
tlsCA:
  enabled: true
  secretName: nats-server-tls
  key: ca.crt

config:
  cluster:
    enabled: true
    replicas: 3
    name: nats
    tls:
      enabled: true
      secretName: nats-server-tls
  
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
    enabled: true
    port: 7422
    # Leaf nodes authenticate using LEAF_ACCOUNT credentials from SCP
    # Run 'make setup-leaf-account' after deployment to configure
    tls:
      enabled: true
      secretName: nats-server-tls
  
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

configMap:
  name: nats-config

service:
  name: nats
  ports:
    nats:
      port: 4222
    leafnodes:
      enabled: true
      port: 7422
    monitor:
      enabled: true
      port: 8222

headlessService:
  name: nats-headless

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
  name: nats

podTemplate:
  configChecksumAnnotation: true
