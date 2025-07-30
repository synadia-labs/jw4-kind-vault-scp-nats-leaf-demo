.PHONY: help apply destroy plan init fmt validate test port-forward logs clean status

# Configuration
LEAF_CLUSTER_NAME ?= nats-leaf

# Default target
help:
	@echo "NATS Leaf Terraform Commands:"
	@echo "  make init        - Initialize Terraform"
	@echo "  make apply       - Deploy NATS leaf cluster"
	@echo "  make destroy     - Destroy NATS leaf cluster"
	@echo "  make plan        - Show deployment plan"
	@echo "  make test        - Test NATS leaf deployment"
	@echo "  make port-forward - Port forward to NATS leaf (4222:4222)"
	@echo "  make logs        - Show NATS leaf logs"
	@echo "  make clean       - Clean generated files"

# Initialize Terraform
init:
	terraform init

# Format Terraform files
fmt:
	terraform fmt -recursive .

# Validate Terraform configuration
validate: init
	terraform validate

# Check for leaf credentials and operator config
check-leaf-creds:
	@if [ ! -f ../nats-core-tf/.leaf.creds ]; then \
		echo "ERROR: Leaf credentials not found. Please deploy NATS core first."; \
		echo "  cd ../nats-core-tf && make apply"; \
		exit 1; \
	fi
	@echo "✓ Leaf credentials found"
	@if [ ! -f ../nats-core-tf/.operator-jwt ]; then \
		echo "ERROR: Operator JWT not found. Please deploy NATS core first."; \
		exit 1; \
	fi
	@echo "✓ Operator config found"

# Generate values.yaml from template
values.yaml: values.yaml.tpl check-leaf-creds
	@echo "Generating values.yaml from template..."
	@if [ -f ../nats-core-tf/.leaf.creds ]; then \
		cp ../nats-core-tf/.leaf.creds .leaf.creds; \
	fi
	@if [ -f ../nats-core-tf/.operator-jwt ]; then \
		cp ../nats-core-tf/.operator-jwt .operator-jwt; \
		cp ../nats-core-tf/.system-account .system-account; \
		cp ../nats-core-tf/.system-account-id .system-account-id; \
		cp ../nats-core-tf/.resolver-preload .resolver-preload; \
		cp ../nats-core-tf/.leaf-account-id .leaf-account-id 2>/dev/null || true; \
	fi
	@export OPERATOR_JWT=$$(cat .operator-jwt 2>/dev/null | sed 's/^/      /' || echo "      # No operator JWT") && \
	export SYSTEM_ACCOUNT=$$(cat .system-account 2>/dev/null | sed 's/^/      /' || echo "      # No system account") && \
	export SYSTEM_ACCOUNT_ID=$$(cat .system-account-id 2>/dev/null || echo "") && \
	export RESOLVER_PRELOAD=$$(cat .resolver-preload 2>/dev/null || echo "        {}") && \
	export LEAF_ACCOUNT_ID=$$(if [ -f ../nats-core-tf/.leaf-jwt ]; then \
		python3 -c "import json, base64; jwt=open('../nats-core-tf/.leaf-jwt').read().strip().split('.')[1]; jwt+='='*(-len(jwt)%4); print(json.loads(base64.b64decode(jwt))['sub'])" 2>/dev/null || echo ""; \
	else \
		echo ""; \
	fi) && \
	envsubst < values.yaml.tpl > values.yaml
	@echo "values.yaml generated successfully"
	@if [ -f ../nats-core-tf/.leaf-jwt ]; then \
		echo "✓ Leaf account ID extracted from JWT: $$(python3 -c "import json, base64; jwt=open('../nats-core-tf/.leaf-jwt').read().strip().split('.')[1]; jwt+='='*(-len(jwt)%4); print(json.loads(base64.b64decode(jwt))['sub'])" 2>/dev/null || echo "ERROR")"; \
	fi

# Plan deployment
plan: init values.yaml
	terraform plan

# Apply deployment
apply: init values.yaml
	terraform apply -auto-approve

# Destroy deployment
destroy: init
	@echo "Destroying Terraform resources..."
	terraform destroy -auto-approve
	@echo "Cleaning up generated files..."
	@rm -f values.yaml .leaf.creds .operator-jwt .system-account .system-account-id .resolver-preload .leaf-account-id
	@echo "✓ Cleanup complete"

# Test NATS leaf deployment
test:
	@bash scripts/test-leaf.sh

# Port forward to NATS leaf
port-forward:
	@echo "Port forwarding NATS leaf 4222:4222..."
	@echo "Press Ctrl+C to stop"
	kubectl port-forward -n $(shell terraform output -raw namespace 2>/dev/null || echo "leaf-nats") \
		svc/$(shell terraform output -raw service_name 2>/dev/null || echo "nats-leaf") 4222:4222

# Show NATS leaf logs
logs:
	kubectl logs -n $(shell terraform output -raw namespace 2>/dev/null || echo "leaf-nats") \
		-l app.kubernetes.io/name=nats --tail=100 -f

# Clean generated files
clean:
	@rm -f values.yaml .leaf.creds .operator-jwt .system-account .system-account-id .resolver-preload .leaf-account-id
	@rm -f terraform.tfstate* terraform.tfplan
	@rm -rf .terraform
	@echo "Cleaned generated files"

# Show comprehensive status
status:
	@echo "=== NATS Leaf Status ==="
	@echo ""
	@echo "Namespace: $(shell terraform output -raw namespace 2>/dev/null || echo 'leaf-nats')"
	@echo ""
	@echo "Pods:"
	@kubectl get pods -n $(shell terraform output -raw namespace 2>/dev/null || echo 'leaf-nats') -l app.kubernetes.io/name=nats --no-headers | awk '{printf "  %-25s %-10s %s\n", $$1, $$2, $$3}' || echo "  No NATS pods found"
	@echo ""
	@echo "Services:"
	@kubectl get svc -n $(shell terraform output -raw namespace 2>/dev/null || echo 'leaf-nats') --no-headers | awk '{printf "  %-25s %-15s %s\n", $$1, $$2, $$4}' || echo "  No services found"
	@echo ""
	@echo "StatefulSet:"
	@kubectl get statefulset -n $(shell terraform output -raw namespace 2>/dev/null || echo 'leaf-nats') --no-headers | awk '{printf "  %-25s %s\n", $$1, $$2}' || echo "  No statefulset found"
	@echo ""
	@echo "PVCs:"
	@kubectl get pvc -n $(shell terraform output -raw namespace 2>/dev/null || echo 'leaf-nats') --no-headers | awk '{printf "  %-35s %-10s %s\n", $$1, $$2, $$3}' || echo "  No PVCs found"
	@echo ""
	@echo "Leaf Node Status:"
	@for i in 0 1 2; do \
		POD="nats-leaf-$$i"; \
		if kubectl get pod -n $(shell terraform output -raw namespace 2>/dev/null || echo 'leaf-nats') $$POD >/dev/null 2>&1; then \
			echo "  $$POD:"; \
			kubectl exec -n $(shell terraform output -raw namespace 2>/dev/null || echo 'leaf-nats') $$POD -- wget -q -O - http://localhost:8222/varz 2>/dev/null | grep -E '"server_id"|"version"' | sed 's/^/    /' || echo "    Unable to get server info"; \
			REMOTE=$$(kubectl exec -n $(shell terraform output -raw namespace 2>/dev/null || echo 'leaf-nats') $$POD -- wget -q -O - http://localhost:8222/leafz 2>/dev/null | grep -E '"leafnodes"' | grep -o '[0-9]*' || echo "0"); \
			echo "    Remote connections: $$REMOTE"; \
		fi; \
	done
	@echo ""
	@echo "Remote Connection to Core:"
	@kubectl logs -n $(shell terraform output -raw namespace 2>/dev/null || echo 'leaf-nats') nats-leaf-0 nats 2>/dev/null | grep -E "Leafnode connection created" | tail -3 | sed 's/^/  /' || echo "  No connection logs found"
	@echo ""
	@echo "Credentials:"
	@if [ -f .leaf.creds ]; then \
		echo "  ✓ Leaf credentials configured"; \
		echo "  Remote URL: $(shell grep -E "remotes.*url" values.yaml 2>/dev/null | grep -o '"[^"]*"' | tr -d '"' || echo 'Not found')"; \
	else \
		echo "  ✗ Leaf credentials not found"; \
	fi
