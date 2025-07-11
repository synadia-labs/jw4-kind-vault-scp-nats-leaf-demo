output "cluster_name" {
  description = "Name of the Kubernetes cluster"
  value       = var.cluster_name
}

output "kubeconfig_path" {
  description = "Path to the kubeconfig file"
  value       = local.kubeconfig
}

output "context_name" {
  description = "kubectl context name for this cluster"
  value       = "kind-${var.cluster_name}"
}

output "cluster_endpoint" {
  description = "Kubernetes API endpoint"
  value       = "https://127.0.0.1:6443"
}