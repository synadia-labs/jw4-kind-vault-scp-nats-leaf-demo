# NATS Leaf Helm Values
# Generated from template - DO NOT EDIT DIRECTLY

config:
  cluster:
    enabled: true
    replicas: 3
    name: nats-leaf
  
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
      - urls:
        - "nats://nats.nats.svc.cluster.local:7422"
        credentials: "/etc/nats-creds/leaf.creds"
        account: "${LEAF_ACCOUNT_ID}"

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
