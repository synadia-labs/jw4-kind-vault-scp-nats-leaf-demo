.PHONY: help init plan apply destroy clean status test-cert

# Default KUBECONFIG
KUBECONFIG ?= $(HOME)/.kube/config
export KUBECONFIG

# Check if ROOT_CA_PATH is set
check-root-ca:
	@if [ -z "$(ROOT_CA_PATH)" ]; then \
		echo "ERROR: ROOT_CA_PATH environment variable must be set"; \
		echo "Example: export ROOT_CA_PATH=/path/to/your/ca/files"; \
		exit 1; \
	fi
	@if [ ! -f "$(ROOT_CA_PATH)/root-ca.crt" ]; then \
		echo "ERROR: root-ca.crt not found in $(ROOT_CA_PATH)"; \
		exit 1; \
	fi
	@if [ ! -f "$(ROOT_CA_PATH)/root-ca.key" ]; then \
		echo "ERROR: root-ca.key not found in $(ROOT_CA_PATH)"; \
		exit 1; \
	fi

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: check-root-ca ## Initialize Terraform
	@echo "Initializing Terraform..."
	@terraform init

plan: check-root-ca ## Plan Terraform changes
	@echo "Planning Terraform changes..."
	@terraform plan -var="root_ca_path=$(ROOT_CA_PATH)"

apply: check-root-ca ## Deploy Vault and configure PKI
	@echo "Deploying Vault..."
	@terraform apply -auto-approve -var="root_ca_path=$(ROOT_CA_PATH)"

destroy: ## Destroy Vault installation
	@echo "Destroying Vault..."
	@terraform destroy -auto-approve -var="root_ca_path=$(ROOT_CA_PATH)" || true

clean: destroy ## Clean up all resources
	@echo "Cleaning up..."
	@rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
	@kubectl delete namespace vault --ignore-not-found=true
	@kubectl delete namespace cert-manager --ignore-not-found=true

status: ## Check Vault status
	@echo "=== Vault Status ==="
	@kubectl get pods -n vault 2>/dev/null || echo "Vault namespace not found"
	@echo ""
	@echo "=== cert-manager Status ==="
	@kubectl get pods -n cert-manager 2>/dev/null || echo "cert-manager namespace not found"
	@echo ""
	@echo "=== ClusterIssuer Status ==="
	@kubectl get clusterissuer vault-issuer 2>/dev/null || echo "ClusterIssuer not found"

port-forward: ## Set up port forwarding to Vault UI
	@echo "Setting up port forwarding to Vault UI..."
	@echo "Vault UI will be available at: http://localhost:30200"
	@echo "Token: root"
	@kubectl port-forward -n vault svc/vault-ui 30200:8200

test-cert: ## Create a test certificate
	@bash $(CURDIR)/scripts/test-cert.sh

logs: ## Show Vault logs
	@kubectl logs -n vault -l app.kubernetes.io/name=vault --tail=50

vault-cli: ## Open Vault CLI in pod
	@echo "Opening Vault CLI session..."
	@echo "Token: root"
	@kubectl exec -it -n vault vault-0 -- /bin/sh