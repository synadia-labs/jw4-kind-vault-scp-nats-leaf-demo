variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = ""
}

variable "nats_namespace" {
  description = "Kubernetes namespace for NATS"
  type        = string
  default     = "nats"
}

variable "create_namespace" {
  description = "Create the namespace if it doesn't exist"
  type        = bool
  default     = true
}

variable "release_name" {
  description = "Helm release name"
  type        = string
  default     = "nats"
}

variable "nats_helm_repository" {
  description = "NATS Helm repository URL"
  type        = string
  default     = "https://nats-io.github.io/k8s/helm/charts/"
}

variable "nats_helm_chart" {
  description = "NATS Helm chart name"
  type        = string
  default     = "nats"
}

variable "nats_chart_version" {
  description = "Version of NATS Helm chart"
  type        = string
  default     = "1.3.9"
}

variable "helm_timeout" {
  description = "Helm deployment timeout in seconds"
  type        = number
  default     = 600
}

variable "scp_namespace" {
  description = "Namespace where SCP is installed"
  type        = string
  default     = "scp"
}

variable "scp_system_name" {
  description = "Name for the NATS system in SCP"
  type        = string
  default     = "nats-core"
}

variable "scp_team_name" {
  description = "Team name in SCP for NATS system"
  type        = string
  default     = "nats-team"
}

variable "enable_monitoring" {
  description = "Enable Prometheus monitoring"
  type        = bool
  default     = false
}

variable "cluster_name" {
  description = "NATS cluster name"
  type        = string
  default     = "nats-core"
}

variable "replicas" {
  description = "Number of NATS replicas"
  type        = number
  default     = 3
}

variable "enable_jetstream" {
  description = "Enable JetStream"
  type        = bool
  default     = true
}

variable "jetstream_storage_size" {
  description = "JetStream storage size"
  type        = string
  default     = "10Gi"
}

variable "jetstream_memory_storage_size" {
  description = "JetStream memory storage size"
  type        = string
  default     = "1Gi"
}

variable "enable_auth_callout" {
  description = "Enable auth callout to SCP"
  type        = bool
  default     = true
}

variable "enable_leafnodes" {
  description = "Enable leaf node connections"
  type        = bool
  default     = true
}

variable "leafnode_port" {
  description = "Port for leaf node connections"
  type        = number
  default     = 7422
}

variable "client_port" {
  description = "Port for client connections"
  type        = number
  default     = 4222
}

variable "cluster_port" {
  description = "Port for cluster connections"
  type        = number
  default     = 6222
}

variable "monitor_port" {
  description = "Port for monitoring endpoint"
  type        = number
  default     = 8222
}

variable "metrics_port" {
  description = "Port for Prometheus metrics"
  type        = number
  default     = 7777
}

