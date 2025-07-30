# NATS Leaf Node Cluster Makefile

.DEFAULT_GOAL := help
.PHONY: help init plan apply test port-forward clean destroy

# Configuration
TERRAFORM := terraform
KUBECTL := kubectl
NAMESPACE := leaf-nats

## Help
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Targets:'
	@grep -E '^[a-zA-Z0-9_-]+:.*## .*' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*## "}; {printf "  %-20s %s\n", $$1, $$2}'

## Terraform Operations
init: check-leaf-creds ## Initialize Terraform
	$(TERRAFORM) init

plan: check-leaf-creds ## Plan Terraform deployment
	$(TERRAFORM) plan -out=tfplan

apply: check-leaf-creds ## Deploy NATS leaf cluster
	@echo "Deploying NATS leaf cluster using Helm..."
	./deploy.sh

check-leaf-creds: ## Check if leaf credentials exist
	@if [ ! -f ".leaf.creds" ]; then \
		echo "ERROR: Leaf credentials not found!"; \
		echo ""; \
		echo "Please ensure .leaf.creds file exists in nats-leaf-tf directory"; \
		echo ""; \
		exit 1; \
	fi
	@echo "✓ Leaf credentials found"

create-namespace: ## Create namespace if it doesn't exist
	@$(KUBECTL) get namespace $(NAMESPACE) >/dev/null 2>&1 || \
		(echo "Creating namespace $(NAMESPACE)..." && $(KUBECTL) create namespace $(NAMESPACE))

create-secret: ## Create leaf credentials secret if it doesn't exist
	@$(KUBECTL) get secret leaf-credentials -n $(NAMESPACE) >/dev/null 2>&1 || \
		(echo "Creating leaf credentials secret..." && \
		$(KUBECTL) create secret generic leaf-credentials \
			--from-file=leaf.creds=.leaf.creds -n $(NAMESPACE))

destroy: ## Destroy Terraform resources
	$(TERRAFORM) destroy -auto-approve

## NATS Operations
test: ## Test leaf NATS cluster
	@echo "Testing NATS leaf cluster..."
	@$(KUBECTL) get pods -n $(NAMESPACE)
	@echo ""
	@echo "Checking leaf node connection to core cluster..."
	@$(KUBECTL) exec -n $(NAMESPACE) nats-leaf-0 -- nats server check connection --server=nats://localhost:4222 || echo "NATS CLI not available in pod"

port-forward: ## Port forward to leaf NATS for local access
	@echo "Port forwarding leaf NATS cluster..."
	@echo "Client port: http://localhost:4222"
	@echo "Monitoring: http://localhost:8222"
	@echo "Press Ctrl+C to stop"
	$(KUBECTL) port-forward -n $(NAMESPACE) svc/nats-leaf 4222:4222 8222:8222

logs: ## Show NATS leaf cluster logs
	$(KUBECTL) logs -n $(NAMESPACE) -l app.kubernetes.io/name=nats -f

## Status Operations
status: ## Show deployment status
	@echo "=== NATS Leaf Cluster Status ==="
	@$(KUBECTL) get all -n $(NAMESPACE) || echo "Namespace $(NAMESPACE) not found"
	@echo ""
	@echo "=== Pod Details ==="
	@$(KUBECTL) describe pods -n $(NAMESPACE) -l app.kubernetes.io/name=nats || echo "No NATS pods found"

check-deps: ## Check if required dependencies are available
	@echo "Checking dependencies..."
	@command -v $(TERRAFORM) >/dev/null 2>&1 || { echo "Terraform not found. Please install Terraform."; exit 1; }
	@command -v $(KUBECTL) >/dev/null 2>&1 || { echo "kubectl not found. Please install kubectl."; exit 1; }
	@$(KUBECTL) cluster-info >/dev/null 2>&1 || { echo "Cannot connect to Kubernetes cluster."; exit 1; }
	@echo "✓ All dependencies are available"

## Cleanup Operations
clean: ## Clean up local files and reset state
	@echo "Cleaning up local files..."
	rm -f tfplan
	rm -f .terraform.lock.hcl
	rm -rf .terraform/
	@echo "✓ Cleanup complete"