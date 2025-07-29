output "namespace" {
  description = "Kubernetes namespace where NATS is installed"
  value       = var.nats_namespace
}

output "service_name" {
  description = "NATS service name"
  value       = var.release_name
}

output "nats_cluster_url" {
  description = "NATS cluster connection URL"
  value       = "nats://${var.release_name}.${var.nats_namespace}.svc.cluster.local:${var.client_port}"
}

output "nats_external_url" {
  description = "NATS external connection URL (requires port-forward or LoadBalancer)"
  value       = "nats://localhost:${var.client_port}"
}

output "leafnode_url" {
  description = "URL for leaf node connections"
  value       = var.enable_leafnodes ? "nats://${var.release_name}-leafnodes.${var.nats_namespace}.svc.cluster.local:${var.leafnode_port}" : null
}

output "monitoring_url" {
  description = "NATS monitoring endpoint URL"
  value       = "http://${var.release_name}.${var.nats_namespace}.svc.cluster.local:${var.monitor_port}"
}

output "metrics_url" {
  description = "Prometheus metrics endpoint URL"
  value       = "http://${var.release_name}.${var.nats_namespace}.svc.cluster.local:${var.metrics_port}/metrics"
}

output "system_account_exists" {
  description = "Whether system account credentials were configured"
  value       = fileexists("${path.module}/.system-account")
}

output "operator_jwt_exists" {
  description = "Whether operator JWT was configured"
  value       = fileexists("${path.module}/.operator-jwt")
}

output "port_forward_command" {
  description = "Command to access NATS locally"
  value       = "kubectl port-forward -n ${var.nats_namespace} svc/${var.release_name} ${var.client_port}:${var.client_port}"
}

output "test_connection_command" {
  description = "Command to test NATS connection"
  value       = "nats --server nats://localhost:${var.client_port} server check connection"
}

