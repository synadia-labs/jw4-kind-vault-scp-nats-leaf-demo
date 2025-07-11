kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
- role: control-plane
%{ for i in range(node_count) ~}
- role: worker
%{ endfor ~}
networking:
  podSubnet: "10.244.0.0/16"
  serviceSubnet: "10.96.0.0/12"