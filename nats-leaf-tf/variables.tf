# Leaf NATS Cluster Variables

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = ""
}

variable "nats_namespace" {
  description = "Kubernetes namespace for NATS leaf cluster"
  type        = string
  default     = "leaf-nats"
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "nats-leaf"
}

variable "helm_repository" {
  description = "NATS Helm repository URL"
  type        = string
  default     = "https://nats-io.github.io/k8s/helm/charts/"
}

variable "helm_chart" {
  description = "NATS Helm chart name"
  type        = string
  default     = "nats"
}

variable "helm_chart_version" {
  description = "NATS Helm chart version"
  type        = string
  default     = "1.3.9"
}

variable "helm_timeout" {
  description = "Helm deployment timeout"
  type        = number
  default     = 600
}

variable "cluster_size" {
  description = "Number of NATS leaf nodes"
  type        = number
  default     = 1
}

variable "jetstream_enabled" {
  description = "Enable JetStream on leaf nodes"
  type        = bool
  default     = true
}

variable "jetstream_storage_size" {
  description = "JetStream storage size per node"
  type        = string
  default     = "10Gi"
}

variable "leaf_remote_url" {
  description = "Core NATS cluster URL for leaf connection"
  type        = string
  default     = "nats://nats.nats.svc.cluster.local:7422"
}

variable "leaf_credentials" {
  description = "Path to leaf node credentials file"
  type        = string
  default     = "../nats-core-tf/.leaf.creds"
}

variable "enable_monitoring" {
  description = "Enable NATS monitoring endpoint"
  type        = bool
  default     = true
}

variable "resources" {
  description = "Resource requests and limits for NATS pods"
  type = object({
    requests = object({
      cpu    = string
      memory = string
    })
    limits = object({
      cpu    = string
      memory = string
    })
  })
  default = {
    requests = {
      cpu    = "100m"
      memory = "128Mi"
    }
    limits = {
      cpu    = "500m"
      memory = "512Mi"
    }
  }
}

