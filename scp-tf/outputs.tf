output "admin_password" {
  description = "Admin user password (check .admin-password file)"
  value       = "Stored in .admin-password file"
  sensitive   = false
}

output "api_token" {
  description = "API token for automation (check .api-token file)"
  value       = "Stored in .api-token file"
  sensitive   = false
}

output "api_url" {
  description = "SCP API endpoint URL"
  value       = "http://scp-control-plane.${var.scp_namespace}:8080"
}

output "console_url" {
  description = "Web console URL"
  value       = "http://localhost:${var.node_port}"
}

output "namespace" {
  description = "Kubernetes namespace where SCP is installed"
  value       = var.scp_namespace
}

output "port_forward_command" {
  description = "Command to access SCP UI"
  value       = "kubectl port-forward -n ${var.scp_namespace} svc/scp-control-plane ${var.node_port}:80"
}

output "helm_repository" {
  description = "Helm repository URL used for deployment"
  value       = var.synadia_helm_repository
}
