#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."

echo "=== NATS Credentials ==="
echo ""

# Check if operator JWT exists
if [ -f "$ROOT_DIR/.operator-jwt" ]; then
  echo "Operator JWT:"
  echo "-------------"
  cat "$ROOT_DIR/.operator-jwt"
  echo ""
else
  echo "No operator JWT found. Run 'make setup-system' first."
fi

# Check if system account exists
if [ -f "$ROOT_DIR/.system-account" ] && [ -s "$ROOT_DIR/.system-account" ]; then
  echo ""
  echo "System Account Credentials:"
  echo "--------------------------"
  cat "$ROOT_DIR/.system-account"
  echo ""
else
  echo ""
  echo "No system account credentials found."
fi

# Get connection info from Terraform outputs if available
if terraform output >/dev/null 2>&1; then
  echo ""
  echo "Connection Information:"
  echo "----------------------"
  echo "Internal URL: $(terraform output -raw nats_cluster_url 2>/dev/null || echo 'N/A')"
  echo "External URL: $(terraform output -raw nats_external_url 2>/dev/null || echo 'N/A')"
  echo "Leafnode URL: $(terraform output -raw leafnode_url 2>/dev/null || echo 'N/A')"
  echo ""
  echo "To connect locally:"
  echo "$(terraform output -raw port_forward_command 2>/dev/null)"
else
  echo ""
  echo "Deploy NATS first with 'make apply' to see connection information."
fi

