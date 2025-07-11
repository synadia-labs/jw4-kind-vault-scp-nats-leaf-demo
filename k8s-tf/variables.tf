variable "cluster_name" {
  description = "Name of the KIND cluster"
  type        = string
  default     = "kind-demo"
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file (uses KUBECONFIG env if not set)"
  type        = string
  default     = ""
}

variable "node_count" {
  description = "Number of worker nodes"
  type        = number
  default     = 2
}