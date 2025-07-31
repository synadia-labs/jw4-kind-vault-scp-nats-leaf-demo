.PHONY: help init plan apply destroy clean get-credentials get-token port-forward logs status

# Default KUBECONFIG
KUBECONFIG ?= $(HOME)/.kube/config
export KUBECONFIG

# Terraform variables
TF_VARS =

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-20s\033[0m %s\n", $$1, $$2}'

init: ## Initialize Terraform
	@echo "Initializing Terraform..."
	@terraform init

plan: ## Plan Terraform changes
	@echo "Planning Terraform changes..."
	@terraform plan $(TF_VARS)

apply: ## Deploy SCP
	@echo "Deploying Synadia Control Plane..."
	@terraform apply -auto-approve $(TF_VARS)

destroy: ## Destroy SCP installation
	@echo "Destroying SCP..."
	@terraform destroy -auto-approve $(TF_VARS)
	@echo "Cleaning up persistent volumes..."
	@kubectl delete pvc -n scp --all --ignore-not-found=true 2>/dev/null || true
	@echo "Cleaning up all generated files..."
	@rm -rf .terraform .terraform.lock.hcl terraform.tfstate* *.tfplan
	@rm -f .admin-password .api-token .team-id .project-id control-plane-values.yaml
	@rm -f scp-credentials.json .admin-status
	@rm -f *.jwt license.jwt
	@rm -f override.tf override.tf.json *_override.tf *_override.tf.json
	@rm -f crash.log crash.*.log

clean: destroy ## Clean up all resources and files
	@echo "Cleaning up..."
	@rm -rf .terraform .terraform.lock.hcl terraform.tfstate*
	@rm -f .admin-password .api-token .team-id .project-id control-plane-values.yaml
	@kubectl delete pvc -n scp --all --ignore-not-found=true 2>/dev/null || true
	@kubectl delete namespace scp --ignore-not-found=true --timeout=60s

get-credentials: ## Show admin credentials
	@bash $(CURDIR)/scripts/get-credentials.sh

get-token: ## Get API token (for use in scripts)
	@cat .api-token 2>/dev/null || (echo "ERROR: Token not found - run 'make apply' first" >&2; exit 1)

port-forward: ## Set up port forwarding to access SCP UI
	@echo "Setting up port forwarding to SCP..."
	@echo "SCP UI will be available at: http://localhost:30080"
	@echo "Press Ctrl+C to stop"
	@kubectl port-forward -n scp svc/scp-control-plane 30080:80

logs: ## Show SCP logs
	@kubectl logs -n scp -l app.kubernetes.io/name=control-plane --tail=100 -f

status: ## Check SCP status
	@echo "=== SCP Status ==="
	@kubectl get pods -n scp 2>/dev/null || echo "SCP namespace not found"
	@echo ""
	@echo "=== Services ==="
	@kubectl get svc -n scp 2>/dev/null || true
	@echo ""
	@echo "=== Secrets ==="
	@kubectl get secrets -n scp 2>/dev/null || true

test: ## Test SCP deployment
	@bash $(CURDIR)/scripts/test-scp.sh

test-api: ## Test SCP API
	@echo "Testing SCP API..."
	@TOKEN=$$(cat .api-token 2>/dev/null) || (echo "ERROR: Token not found" >&2; exit 1); \
	kubectl port-forward -n scp svc/scp-control-plane 8080:80 >/dev/null 2>&1 & \
	PF_PID=$$!; \
	sleep 3; \
	echo "Testing API connectivity..."; \
	HTTP_STATUS=$$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/); \
	if [ "$$HTTP_STATUS" == "200" ]; then \
		echo "✓ API is reachable (HTTP $$HTTP_STATUS)"; \
	else \
		echo "✗ API not reachable (HTTP $$HTTP_STATUS)"; \
	fi; \
	echo "Testing authenticated endpoint..."; \
	HTTP_STATUS=$$(curl -s -o /dev/null -w "%{http_code}" -H "Authorization: Bearer $$TOKEN" http://localhost:8080/api/core/beta/admin/app-user); \
	if [ "$$HTTP_STATUS" == "403" ] || [ "$$HTTP_STATUS" == "401" ]; then \
		echo "✓ API authentication working (HTTP $$HTTP_STATUS)"; \
	else \
		echo "✗ Unexpected HTTP status: $$HTTP_STATUS"; \
	fi; \
	kill $$PF_PID 2>/dev/null || true