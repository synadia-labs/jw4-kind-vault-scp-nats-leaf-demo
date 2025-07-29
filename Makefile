# Synadia Demo - Top Level Makefile
# Orchestrates deployment and teardown of all infrastructure components

.PHONY: help init deploy destroy status clean test port-forward stop-port-forward
.DEFAULT_GOAL := help

# Configuration
CLUSTER_NAME ?= synadia-demo

# Project directories in dependency order
K8S_DIR := k8s-tf
VAULT_DIR := vault-tf
SCP_DIR := scp-tf
NATS_CORE_DIR := nats-core-tf
NATS_LEAF_DIR := nats-leaf-tf
DEVICES_DIR := devices

# Colors for output
RED := \033[31m
GREEN := \033[32m
YELLOW := \033[33m
BLUE := \033[34m
RESET := \033[0m

help: ## Show this help message
	@echo "$(BLUE)Synadia Demo Infrastructure$(RESET)"
	@echo "Manages complete NATS infrastructure stack"
	@echo ""
	@echo "$(YELLOW)Usage:$(RESET)"
	@grep -E '^[a-zA-Z0-9_-]+:.*## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  $(GREEN)%-15s$(RESET) %s\n", $$1, $$2}'
	@echo ""
	@echo "$(YELLOW)Configuration:$(RESET)"
	@echo "  CLUSTER_NAME: $(CLUSTER_NAME)"

init: ## Initialize all projects
	@echo "$(BLUE)Initializing all projects...$(RESET)"
	@cd $(K8S_DIR) && terraform init
	@cd $(VAULT_DIR) && terraform init
	@cd $(SCP_DIR) && terraform init
	@cd $(NATS_CORE_DIR) && terraform init
	@if [ -d $(NATS_LEAF_DIR) ]; then cd $(NATS_LEAF_DIR) && terraform init; fi
	@echo "$(GREEN)✓ All projects initialized$(RESET)"

deploy: ## Deploy complete infrastructure stack
	@echo "$(BLUE)Deploying complete Synadia infrastructure...$(RESET)"
	@$(MAKE) deploy-k8s
	@$(MAKE) deploy-vault
	@$(MAKE) deploy-scp
	@$(MAKE) deploy-nats-core
	@if [ -d $(NATS_LEAF_DIR) ]; then $(MAKE) deploy-nats-leaf; fi
	@echo ""
	@echo "$(GREEN)🎉 Complete infrastructure deployed successfully!$(RESET)"
	@echo ""
	@echo "$(YELLOW)Next steps:$(RESET)"
	@echo "  make status    - Check all components"
	@echo "  make test      - Run integration tests"
	@echo "  make port-forward - Access services locally"

deploy-k8s: ## Deploy Kubernetes cluster
	@echo "$(BLUE)1/4 Deploying Kubernetes cluster...$(RESET)"
	@cd $(K8S_DIR) && make up
	@echo "$(GREEN)✓ Kubernetes cluster ready$(RESET)"

deploy-vault: ## Deploy Vault
	@echo "$(BLUE)2/4 Deploying Vault...$(RESET)"
	@cd $(VAULT_DIR) && make apply
	@echo "$(GREEN)✓ Vault ready$(RESET)"

deploy-scp: ## Deploy Synadia Control Plane
	@echo "$(BLUE)3/4 Deploying Synadia Control Plane...$(RESET)"
	@cd $(SCP_DIR) && make apply
	@echo "$(GREEN)✓ SCP ready$(RESET)"

deploy-nats-core: ## Deploy NATS Core cluster
	@echo "$(BLUE)4/4 Deploying NATS Core...$(RESET)"
	@cd $(NATS_CORE_DIR) && make setup-system
	@cd $(NATS_CORE_DIR) && make apply
	@echo "$(GREEN)✓ NATS Core ready$(RESET)"

deploy-nats-leaf: ## Deploy NATS Leaf clusters (optional)
	@if [ -d $(NATS_LEAF_DIR) ]; then \
		echo "$(BLUE)5/5 Deploying NATS Leaf...$(RESET)"; \
		cd $(NATS_LEAF_DIR) && make apply; \
		echo "$(GREEN)✓ NATS Leaf ready$(RESET)"; \
	else \
		echo "$(YELLOW)NATS Leaf directory not found, skipping...$(RESET)"; \
	fi

status: ## Check status of all components
	@echo "$(BLUE)Infrastructure Status$(RESET)"
	@echo "===================="
	@echo ""
	@echo "$(YELLOW)Kubernetes Cluster:$(RESET)"
	@if kubectl cluster-info >/dev/null 2>&1; then \
		echo "$(GREEN)✓ Cluster accessible$(RESET)"; \
		kubectl get nodes --no-headers | awk '{printf "  Node %-20s %s\n", $$1, $$2}'; \
	else \
		echo "$(RED)✗ Cluster not accessible$(RESET)"; \
	fi
	@echo ""
	@echo "$(YELLOW)Namespaces:$(RESET)"
	@kubectl get ns vault scp nats 2>/dev/null | tail -n +2 | awk '{printf "  %-10s %s\n", $$1, $$2}' || true
	@echo ""
	@echo "$(YELLOW)Pods by Namespace:$(RESET)"
	@for ns in vault scp nats; do \
		if kubectl get ns $$ns >/dev/null 2>&1; then \
			echo "  $$ns:"; \
			kubectl get pods -n $$ns --no-headers 2>/dev/null | awk '{printf "    %-30s %s\n", $$1, $$3}' || echo "    No pods found"; \
		fi; \
	done

test: ## Run tests for all components
	@echo "$(BLUE)Running integration tests...$(RESET)"
	@echo ""
	@echo "$(YELLOW)Testing Vault...$(RESET)"
	@cd $(VAULT_DIR) && make test || echo "$(RED)Vault test failed$(RESET)"
	@echo ""
	@echo "$(YELLOW)Testing SCP...$(RESET)"
	@cd $(SCP_DIR) && make test || echo "$(RED)SCP test failed$(RESET)"
	@echo ""
	@echo "$(YELLOW)Testing NATS Core...$(RESET)"
	@cd $(NATS_CORE_DIR) && make test || echo "$(RED)NATS Core test failed$(RESET)"
	@if [ -d $(NATS_LEAF_DIR) ]; then \
		echo ""; \
		echo "$(YELLOW)Testing NATS Leaf...$(RESET)"; \
		cd $(NATS_LEAF_DIR) && make test || echo "$(RED)NATS Leaf test failed$(RESET)"; \
	fi

port-forward: ## Start port forwarding for all services
	@echo "$(BLUE)Starting port forwarding...$(RESET)"
	@echo "$(YELLOW)Starting background port forwards...$(RESET)"
	@kubectl port-forward -n vault svc/vault 8200:8200 >/dev/null 2>&1 & echo $$! > .vault-pf.pid
	@kubectl port-forward -n scp svc/scp-control-plane 8080:80 >/dev/null 2>&1 & echo $$! > .scp-pf.pid
	@kubectl port-forward -n nats svc/nats 4222:4222 >/dev/null 2>&1 & echo $$! > .nats-pf.pid
	@kubectl port-forward -n nats svc/nats 8222:8222 >/dev/null 2>&1 & echo $$! > .nats-mon-pf.pid
	@sleep 2
	@echo "$(GREEN)Port forwarding active:$(RESET)"
	@echo "  Vault UI:       http://localhost:8200"
	@echo "  SCP UI:         http://localhost:8080"
	@echo "  NATS Client:    nats://localhost:4222"
	@echo "  NATS Monitor:   http://localhost:8222"
	@echo ""
	@echo "$(YELLOW)Use 'make stop-port-forward' to stop$(RESET)"

stop-port-forward: ## Stop all port forwarding
	@echo "$(BLUE)Stopping port forwarding...$(RESET)"
	@for pidfile in .vault-pf.pid .scp-pf.pid .nats-pf.pid .nats-mon-pf.pid; do \
		if [ -f "$$pidfile" ]; then \
			pid=$$(cat "$$pidfile"); \
			kill "$$pid" 2>/dev/null || true; \
			rm -f "$$pidfile"; \
		fi; \
	done
	@echo "$(GREEN)✓ Port forwarding stopped$(RESET)"

clean: ## Clean generated files from all projects
	@echo "$(BLUE)Cleaning generated files...$(RESET)"
	@cd $(K8S_DIR) && make clean 2>/dev/null || true
	@cd $(VAULT_DIR) && make clean 2>/dev/null || true
	@cd $(SCP_DIR) && make clean 2>/dev/null || true
	@cd $(NATS_CORE_DIR) && make clean 2>/dev/null || true
	@if [ -d $(NATS_LEAF_DIR) ]; then cd $(NATS_LEAF_DIR) && make clean 2>/dev/null || true; fi
	@rm -f .*.pid
	@echo "$(GREEN)✓ Cleanup complete$(RESET)"

destroy: stop-port-forward ## Destroy complete infrastructure (with confirmation)
	@echo "$(RED)WARNING: This will destroy ALL infrastructure!$(RESET)"
	@echo "This includes:"
	@echo "  - Kubernetes cluster ($(CLUSTER_NAME))"
	@echo "  - All data in Vault, SCP, and NATS"
	@echo "  - All persistent volumes"
	@echo ""
	@read -p "Type 'yes' to confirm destruction: " confirm && [ "$$confirm" = "yes" ] || (echo "Aborted" && exit 1)
	@echo ""
	@echo "$(BLUE)Destroying infrastructure in reverse order...$(RESET)"
	@$(MAKE) destroy-nats-leaf
	@$(MAKE) destroy-nats-core
	@$(MAKE) destroy-scp
	@$(MAKE) destroy-vault
	@$(MAKE) destroy-k8s
	@$(MAKE) clean
	@echo ""
	@echo "$(GREEN)🗑️  Complete infrastructure destroyed$(RESET)"

destroy-nats-leaf: ## Destroy NATS Leaf clusters
	@if [ -d $(NATS_LEAF_DIR) ]; then \
		echo "$(BLUE)Destroying NATS Leaf...$(RESET)"; \
		cd $(NATS_LEAF_DIR) && make destroy 2>/dev/null || true; \
		echo "$(GREEN)✓ NATS Leaf destroyed$(RESET)"; \
	fi

destroy-nats-core: ## Destroy NATS Core cluster
	@echo "$(BLUE)Destroying NATS Core...$(RESET)"
	@cd $(NATS_CORE_DIR) && make destroy 2>/dev/null || true
	@echo "$(GREEN)✓ NATS Core destroyed$(RESET)"

cleanup-nats-scp: ## Clean up NATS system from SCP only
	@echo "$(BLUE)Cleaning up NATS system from SCP...$(RESET)"
	@cd $(NATS_CORE_DIR) && make cleanup-scp

destroy-scp: ## Destroy Synadia Control Plane
	@echo "$(BLUE)Destroying SCP...$(RESET)"
	@cd $(SCP_DIR) && make destroy 2>/dev/null || true
	@echo "$(GREEN)✓ SCP destroyed$(RESET)"

destroy-vault: ## Destroy Vault
	@echo "$(BLUE)Destroying Vault...$(RESET)"
	@cd $(VAULT_DIR) && make destroy 2>/dev/null || true
	@echo "$(GREEN)✓ Vault destroyed$(RESET)"

destroy-k8s: ## Destroy Kubernetes cluster
	@echo "$(BLUE)Destroying Kubernetes cluster...$(RESET)"
	@cd $(K8S_DIR) && make down 2>/dev/null || true
	@echo "$(GREEN)✓ Kubernetes cluster destroyed$(RESET)"

# Quick access targets
logs-vault: ## Show Vault logs
	@kubectl logs -n vault -l app.kubernetes.io/name=vault --tail=50

logs-scp: ## Show SCP logs
	@kubectl logs -n scp -l app.kubernetes.io/name=control-plane --tail=50

logs-nats: ## Show NATS logs
	@kubectl logs -n nats -l app.kubernetes.io/name=nats --tail=50

# Development helpers
dev-shell: ## Open shell in nats-box for testing
	@kubectl exec -it -n nats deployment/nats-box -- sh

vault-status: ## Show Vault status
	@cd $(VAULT_DIR) && make status

scp-info: ## Show SCP connection info
	@echo "$(YELLOW)SCP Access Information:$(RESET)"
	@if [ -f $(SCP_DIR)/.admin-password ]; then \
		echo "  Admin Password: $$(cat $(SCP_DIR)/.admin-password)"; \
	fi
	@if [ -f $(SCP_DIR)/.api-token ]; then \
		echo "  API Token: $$(cat $(SCP_DIR)/.api-token | head -c 20)..."; \
	fi
	@echo "  Web UI: http://localhost:8080 (requires port-forward)"

nats-info: ## Show NATS connection info
	@echo "$(YELLOW)NATS Access Information:$(RESET)"
	@echo "  Client URL: nats://localhost:4222 (requires port-forward)"
	@echo "  Monitor URL: http://localhost:8222 (requires port-forward)"
	@if [ -f $(NATS_CORE_DIR)/.system-account-id ]; then \
		echo "  System Account: $$(cat $(NATS_CORE_DIR)/.system-account-id)"; \
	fi
