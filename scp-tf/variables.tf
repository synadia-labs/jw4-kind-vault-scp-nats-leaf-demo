variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = ""
}

variable "scp_namespace" {
  description = "Kubernetes namespace for SCP"
  type        = string
  default     = "scp"
}

variable "scp_chart_version" {
  description = "Version of SCP Helm chart (leave empty for latest)"
  type        = string
  default     = ""
}

variable "node_port" {
  description = "NodePort for SCP service"
  type        = number
  default     = 30080
}

variable "create_demo_team" {
  description = "Create a demo team and project"
  type        = bool
  default     = true
}

variable "synadia_helm_repository" {
  description = "Synadia Helm repository URL"
  type        = string
  default     = "https://synadia-io.github.io/helm-charts"
}

variable "scp_image_repository" {
  description = "Docker image repository for SCP"
  type        = string
  default     = "control-plane"
}

variable "scp_image_registry" {
  description = "Docker image registry for SCP"
  type        = string
  default     = "registry.synadia.io"
}

variable "scp_image_tag" {
  description = "Docker image tag for SCP (leave empty for chart default)"
  type        = string
  default     = ""
}

variable "scp_image_pull_policy" {
  description = "Image pull policy for SCP"
  type        = string
  default     = "IfNotPresent"
}

variable "scp_image_username" {
  description = "Username for imagePullSecrets"
  type        = string
  default     = ""
}

variable "scp_image_password" {
  description = "Password for imagePullSecrets"
  type        = string
  default     = ""
}
variable "docker_registry_secret" {
  description = "Docker registry authentication (JSON format)"
  type        = string
  sensitive   = true
  default     = ""
}