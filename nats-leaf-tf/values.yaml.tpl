# NATS Leaf Node Configuration
nats:
  image:
    repository: nats
    tag: "2.10.20-alpine"
    pullPolicy: IfNotPresent

# Cluster configuration
cluster:
  enabled: true
  replicas: ${cluster_size}
  
  # Anti-affinity to spread leaf nodes across different nodes
  podAntiAffinity:
    preferredDuringSchedulingIgnoredDuringExecution:
    - weight: 100
      podAffinityTerm:
        labelSelector:
          matchExpressions:
          - key: app.kubernetes.io/name
            operator: In
            values:
            - nats
        topologyKey: kubernetes.io/hostname

# Container configuration
container:
  env:
    GOMEMLIMIT: 75MiB
  
  # Resource management
  resources:
    requests:
      cpu: "${resources.requests.cpu}"
      memory: "${resources.requests.memory}"
    limits:
      cpu: "${resources.limits.cpu}"
      memory: "${resources.limits.memory}"

# NATS Configuration
config:
  # Enable cluster mode
  cluster:
    enabled: true
    port: 6222

  # Client connections
  port: 4222

  # Monitoring
%{ if enable_monitoring ~}
  monitor:
    enabled: true
    port: 8222
%{ endif ~}

  # JetStream configuration
%{ if jetstream_enabled ~}
  jetstream:
    enabled: true
    fileStore:
      pvc:
        size: "${jetstream_storage_size}"
        storageClassName: ""
    memStore:
      enabled: true
      maxSize: 256Mi
%{ endif ~}

  # Leaf node configuration - connect to core NATS
  leafnodes:
    enabled: true
    remotes:
    - url: "${leaf_remote_url}"
      # Use credentials from secret
      credentials: "/etc/nats-creds/leaf.creds"

  # Merge additional configuration
  merge:
    # Basic server settings
    max_connections: 64K
    max_subscriptions: 0
    max_control_line: 4KB
    max_payload: 1MB
    max_pending: 64MB
    
    # Connection timeouts
    ping_interval: "2m"
    ping_max: 2
    write_deadline: "10s"
    
    # Logging
    log_time: true
    debug: false
    trace: false
    logtime: true

# Service configuration
service:
  enabled: true
  type: ClusterIP
  
  # Client connections
  ports:
    client:
      port: 4222
    
    # Cluster connections
    cluster:
      port: 6222
    
%{ if enable_monitoring ~}
    # Monitoring
    monitor:
      port: 8222
%{ endif ~}

# Storage for JetStream and credentials
podTemplate:
  spec:
    volumes:
    - name: leaf-creds
      secret:
        secretName: leaf-credentials
    containers:
    - name: nats
      volumeMounts:
      - name: leaf-creds
        mountPath: /etc/nats-creds
        readOnly: true

# Security context
podSecurityContext:
  fsGroup: 1000
  runAsUser: 1000
  runAsNonRoot: true

# Service account
serviceAccount:
  enabled: true
  name: ""

# Network policies (disabled by default)
networkPolicy:
  enabled: false

# Pod disruption budget
podDisruptionBudget:
  enabled: true
  maxUnavailable: 1

# Horizontal Pod Autoscaler (disabled for leaf nodes)
autoscaling:
  enabled: false