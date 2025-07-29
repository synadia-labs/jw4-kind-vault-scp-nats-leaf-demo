.PHONY: help apply destroy plan init fmt validate test port-forward logs get-credentials clean setup-system cleanup-scp setup-leaf-account

# Configuration
SCP_TEAM_NAME ?= nats-team
SCP_SYSTEM_NAME ?= nats-core

# Default target
help:
	@echo "NATS Core Terraform Commands:"
	@echo "  make init                - Initialize Terraform"
	@echo "  make setup-system        - Create NATS system in SCP and fetch config"
	@echo "  make apply               - Deploy NATS core cluster"
	@echo "  make setup-leaf-account  - Configure LEAF_ACCOUNT for leaf nodes (after apply)"
	@echo "  make test-leaf-connection - Test leaf node connection with local nats-server"
	@echo "  make destroy             - Destroy NATS core cluster"
	@echo "  make plan                - Show deployment plan"
	@echo "  make test                - Test NATS deployment"
	@echo "  make port-forward        - Port forward to NATS (4222:4222)"
	@echo "  make logs                - Show NATS logs"
	@echo "  make clean               - Clean generated files"

# Initialize Terraform
init:
	terraform init

# Format Terraform files
fmt:
	terraform fmt -recursive .

# Validate Terraform configuration
validate: init
	terraform validate

# Create NATS system in SCP and fetch configuration
setup-system:
	@echo "Setting up NATS system in SCP..."
	@if [ ! -f ../scp-tf/.api-token ]; then \
		echo "ERROR: SCP credentials not found. Please deploy SCP first:"; \
		echo "  cd ../scp-tf && make apply"; \
		exit 1; \
	fi
	@SCP_NAMESPACE=$$(cd ../scp-tf && terraform output -raw namespace 2>/dev/null || echo "scp") \
		SCP_TEAM_NAME="$(SCP_TEAM_NAME)" \
		SCP_SYSTEM_NAME="$(SCP_SYSTEM_NAME)" \
		bash scripts/setup-nats-system.sh

# Setup leaf account in SCP (requires NATS to be connected)
setup-leaf-account: ## Create LEAF_ACCOUNT in SCP for leaf node connections
	@echo "Setting up leaf account in SCP..."
	@bash scripts/setup-leaf-account.sh

test-leaf-connection: ## Test leaf node connection with local nats-server
	@echo "Testing leaf node connection..."
	@bash scripts/test-leaf-connection.sh


# Generate values.yaml from template
values.yaml: values.yaml.tpl
	@if [ ! -f .operator-jwt ]; then \
		echo "ERROR: Operator JWT not found. Run 'make setup-system' first."; \
		exit 1; \
	fi
	@echo "Generating values.yaml from template..."
	@export OPERATOR_JWT=$$(cat .operator-jwt 2>/dev/null | sed 's/^/      /' || echo "      # No operator JWT") && \
	export SYSTEM_ACCOUNT=$$(cat .system-account 2>/dev/null | sed 's/^/      /' || echo "      # No system account") && \
	export SYSTEM_ACCOUNT_ID=$$(cat .system-account-id 2>/dev/null || echo "") && \
	export RESOLVER_PRELOAD=$$(cat .resolver-preload 2>/dev/null || echo "        {}") && \
	envsubst < values.yaml.tpl > values.yaml
	@echo "values.yaml generated successfully"

# Plan deployment
plan: init values.yaml
	terraform plan

# Apply deployment
apply: init values.yaml
	terraform apply -auto-approve \
		-var="scp_team_name=$(SCP_TEAM_NAME)" \
		-var="scp_system_name=$(SCP_SYSTEM_NAME)"

# Clean up SCP system only
cleanup-scp: ## Remove NATS system from SCP
	@bash scripts/cleanup-scp-system.sh

# Destroy deployment
destroy: init
	@echo "Cleaning up NATS system from SCP..."
	@bash scripts/cleanup-scp-system.sh || true
	@echo "Destroying Terraform resources..."
	terraform destroy -auto-approve
	@echo "Cleaning up generated files..."
	@rm -f values.yaml
	@rm -f .operator-jwt .system-account .system-account-id .resolver-preload
	@rm -f .system-id .team-id .leaf-account-id .leaf-credentials .leaf-jwt .leaf-group-id .leaf-user-id .leaf-user-credentials.json .leaf-user.creds
	@echo "✓ Cleanup complete"

# Test NATS deployment
test:
	@bash scripts/test-nats.sh

# Port forward to NATS
port-forward:
	@echo "Port forwarding NATS 4222:4222..."
	@echo "Press Ctrl+C to stop"
	kubectl port-forward -n $(shell terraform output -raw namespace 2>/dev/null || echo "nats") \
		svc/$(shell terraform output -raw service_name 2>/dev/null || echo "nats") 4222:4222

# Show NATS logs
logs:
	kubectl logs -n $(shell terraform output -raw namespace 2>/dev/null || echo "nats") \
		-l app.kubernetes.io/name=nats --tail=100 -f

# Get NATS credentials
get-credentials:
	@bash scripts/get-credentials.sh

# Clean generated files
clean:
	@rm -f values.yaml
	@rm -f .operator-jwt .system-account .system-account-id .resolver-preload
	@rm -f .system-id .team-id .leaf-account-id .leaf-credentials .leaf-jwt .leaf-group-id .leaf-user-id .leaf-user-credentials.json .leaf-user.creds
	@rm -f .temp-* terraform.tfstate* terraform.tfplan
	@rm -rf .leaf-test
	@rm -rf .terraform
	@echo "Cleaned generated files"
