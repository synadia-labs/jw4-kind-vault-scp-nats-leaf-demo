variable "root_ca_path" {
  description = "Path to directory containing root-ca.crt and root-ca.key"
  type        = string
}

variable "kubeconfig_path" {
  description = "Path to kubeconfig file"
  type        = string
  default     = ""
}

variable "vault_namespace" {
  description = "Kubernetes namespace for Vault"
  type        = string
  default     = "vault"
}

variable "vault_token" {
  description = "Root token for Vault in dev mode"
  type        = string
  default     = "root"
}

variable "cert_manager_version" {
  description = "Version of cert-manager to install"
  type        = string
  default     = "v1.13.3"
}