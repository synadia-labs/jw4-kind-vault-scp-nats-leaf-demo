output "namespace" {
  description = "Kubernetes namespace where leaf NATS is deployed"
  value       = var.nats_namespace
}

output "service_name" {
  description = "Kubernetes service name for NATS leaf"
  value       = var.release_name
}

output "leaf_cluster_url" {
  description = "Leaf NATS cluster URL for device connections"
  value       = "nats://${var.release_name}.${var.nats_namespace}.svc.cluster.local:4222"
}

output "leaf_cluster_internal_url" {
  description = "Internal cluster URL for leaf node"
  value       = "nats://${var.release_name}.${var.nats_namespace}.svc.cluster.local:6222"
}

output "monitoring_url" {
  description = "NATS monitoring endpoint URL"
  value       = var.enable_monitoring ? "http://${var.release_name}.${var.nats_namespace}.svc.cluster.local:8222" : null
}

output "helm_release_name" {
  description = "Helm release name for the NATS leaf cluster"
  value       = helm_release.nats_leaf.name
}

output "helm_release_version" {
  description = "Helm chart version used for deployment"
  value       = helm_release.nats_leaf.version
}

output "leafnode_connection_info" {
  description = "Information about leaf node connection"
  value = {
    remote_url = var.leaf_remote_url
    namespace  = var.nats_namespace
    service    = var.release_name
    port       = 4222
  }
}

