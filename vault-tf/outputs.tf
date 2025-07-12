output "vault_ui_url" {
  description = "URL to access Vault UI"
  value       = "http://localhost:30200"
}

output "vault_token" {
  description = "Root token for Vault access"
  value       = var.vault_token
  sensitive   = true
}

output "cluster_issuer_name" {
  description = "Name of the ClusterIssuer"
  value       = "vault-issuer"
}

output "vault_namespace" {
  description = "Kubernetes namespace where Vault is installed"
  value       = var.vault_namespace
}

output "pki_mount_path" {
  description = "Path where PKI backend is mounted"
  value       = "pki_int"
}