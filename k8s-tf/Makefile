.PHONY: help up down status clean
.DEFAULT_GOAL := help

# Default kubeconfig if not set
KUBECONFIG ?= $(HOME)/.kube/config

help: ## Show this help message
	@echo "Kubernetes Cluster Management"
	@echo ""
	@echo "Usage:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "Environment:"
	@echo "  KUBECONFIG=$(KUBECONFIG)"

up: check-prereqs ## Create and start the cluster
	@echo "Creating KIND cluster..."
	@mkdir -p "$(dir $(KUBECONFIG))"
	@export KUBECONFIG=$(KUBECONFIG) && terraform init
	@export KUBECONFIG=$(KUBECONFIG) && terraform apply -auto-approve
	@echo ""
	@echo "✅ Cluster is ready!"
	@echo "Next steps:"
	@echo "  kubectl config use-context kind-kind-demo"
	@echo "  kubectl get nodes"

down: ## Destroy the cluster
	@echo "Destroying KIND cluster..."
	@export KUBECONFIG=$(KUBECONFIG) && terraform destroy -auto-approve
	@echo "✅ Cluster destroyed!"

status: ## Show cluster status
	@echo "Cluster Status:"
	@echo "  KUBECONFIG: $(KUBECONFIG)"
	@echo ""
	@if kind get clusters 2>/dev/null | grep -q kind-demo; then \
		echo "  KIND cluster: ✅ running"; \
	else \
		echo "  KIND cluster: ❌ not found"; \
	fi
	@echo ""
	@if [ -f "$(KUBECONFIG)" ]; then \
		echo "  Kubeconfig: ✅ exists"; \
		export KUBECONFIG=$(KUBECONFIG) && kubectl cluster-info --request-timeout=5s 2>/dev/null || echo "  API server: ❌ not reachable"; \
	else \
		echo "  Kubeconfig: ❌ not found"; \
	fi

clean: down ## Destroy cluster and clean up files
	@echo "Cleaning up..."
	@rm -rf .terraform .terraform.lock.hcl terraform.tfstate terraform.tfstate.backup
	@echo "✅ Cleanup complete!"

check-prereqs:
	@echo "Checking prerequisites..."
	@command -v docker >/dev/null 2>&1 || { echo "❌ Docker not found. Please install Docker."; exit 1; }
	@docker info >/dev/null 2>&1 || { echo "❌ Docker not running. Please start Docker."; exit 1; }
	@command -v kind >/dev/null 2>&1 || { echo "❌ KIND not found. Install from https://kind.sigs.k8s.io"; exit 1; }
	@command -v kubectl >/dev/null 2>&1 || { echo "❌ kubectl not found. Please install kubectl."; exit 1; }
	@command -v terraform >/dev/null 2>&1 || { echo "❌ Terraform not found. Please install Terraform."; exit 1; }
	@echo "✅ All prerequisites met!"