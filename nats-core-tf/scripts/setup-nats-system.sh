#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
SCP_DIR="$ROOT_DIR/../scp-tf"

echo "=== Setting up NATS System in SCP ==="

# Check if SCP project exists
if [ ! -d "$SCP_DIR" ]; then
  echo "ERROR: SCP project not found at $SCP_DIR"
  echo "Please ensure the scp-tf project is deployed first."
  exit 1
fi

# Check if SCP credentials exist in the scp-tf project
if [ ! -f "$SCP_DIR/.api-token" ]; then
  echo "ERROR: SCP API token not found at $SCP_DIR/.api-token"
  echo "Please run 'make apply' in the scp-tf project first."
  exit 1
fi

# Get SCP credentials from scp-tf project
echo "Reading SCP credentials from scp-tf project..."
SCP_TOKEN=$(cat "$SCP_DIR/.api-token")
if [ -z "$SCP_TOKEN" ] || [ "$SCP_TOKEN" == "null" ]; then
  echo "ERROR: Invalid SCP API token"
  exit 1
fi

# Get SCP namespace to determine service name
SCP_NAMESPACE="${SCP_NAMESPACE:-scp}"

# Setup port-forward to SCP
echo "Setting up port forward to SCP (namespace: $SCP_NAMESPACE)..."
kubectl port-forward -n $SCP_NAMESPACE svc/scp-control-plane 8080:80 >/dev/null 2>&1 &
PF_PID=$!

cleanup() {
  if [ ! -z "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Wait for port forward
sleep 5

# Test SCP connectivity
echo "Testing SCP connectivity..."
if ! curl -s -H "Authorization: Bearer $SCP_TOKEN" http://localhost:8080/api/core/beta/teams >/dev/null; then
  echo "ERROR: Cannot connect to SCP API"
  exit 1
fi

# Check if team already exists or create one
TEAM_NAME="${SCP_TEAM_NAME:-nats-team}"
echo "Checking for team: $TEAM_NAME"

TEAM_ID=""
TEAMS_RESPONSE=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" http://localhost:8080/api/core/beta/teams)
TEAM_ID=$(echo "$TEAMS_RESPONSE" | jq -r ".items[] | select(.name==\"$TEAM_NAME\") | .id" | head -1)

if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" == "null" ]; then
  echo "Creating team: $TEAM_NAME"
  CREATE_TEAM_RESPONSE=$(curl -s -X POST http://localhost:8080/api/core/beta/teams \
    -H "Authorization: Bearer $SCP_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\":\"$TEAM_NAME\"}")

  TEAM_ID=$(echo "$CREATE_TEAM_RESPONSE" | jq -r '.id')
  if [ -z "$TEAM_ID" ] || [ "$TEAM_ID" == "null" ]; then
    echo "ERROR: Failed to create team"
    echo "Response: $CREATE_TEAM_RESPONSE"
    exit 1
  fi
  echo "Team created with ID: $TEAM_ID"
else
  echo "Team already exists with ID: $TEAM_ID"
fi

# Save team ID
echo "$TEAM_ID" >"$ROOT_DIR/.team-id"

# Check if system already exists or create one
SYSTEM_NAME="${SCP_SYSTEM_NAME:-nats-core}"
echo "Checking for system: $SYSTEM_NAME"

SYSTEM_ID=""
SYSTEMS_RESPONSE=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" "http://localhost:8080/api/core/beta/teams/$TEAM_ID/systems")
SYSTEM_ID=$(echo "$SYSTEMS_RESPONSE" | jq -r ".items[] | select(.name==\"$SYSTEM_NAME\") | .id" | head -1)

if [ -z "$SYSTEM_ID" ] || [ "$SYSTEM_ID" == "null" ]; then
  echo "Creating system: $SYSTEM_NAME"
  # Create system with Agent connection type (managed by NATS agents in Kubernetes)
  CREATE_SYSTEM_RESPONSE=$(curl -s -X POST "http://localhost:8080/api/core/beta/teams/$TEAM_ID/systems" \
    -H "Authorization: Bearer $SCP_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\":\"$SYSTEM_NAME\",
      \"url\":\"nats://nats.nats.svc.cluster.local:4222\",
      \"connection_type\":\"Direct\",
      \"jetstream_enabled\":true
    }")

  SYSTEM_ID=$(echo "$CREATE_SYSTEM_RESPONSE" | jq -r '.id')
  if [ -z "$SYSTEM_ID" ] || [ "$SYSTEM_ID" == "null" ]; then
    echo "ERROR: Failed to create system"
    echo "Response: $CREATE_SYSTEM_RESPONSE"
    exit 1
  fi
  echo "System created with ID: $SYSTEM_ID"
else
  echo "System already exists with ID: $SYSTEM_ID"
fi

# Save system ID
echo "$SYSTEM_ID" >"$ROOT_DIR/.system-id"

# Get system export to extract operator JWT and other configs
echo "Fetching system configuration..."
EXPORT_RESPONSE=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
  "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID/export")

# Extract operator JWT from the nested structure
OPERATOR_JWT=$(echo "$EXPORT_RESPONSE" | jq -r '.operator.jwt // empty')
if [ -z "$OPERATOR_JWT" ]; then
  echo "ERROR: Failed to get operator JWT from system export"
  echo "Response: $EXPORT_RESPONSE"
  exit 1
fi

# Save operator JWT
echo "$OPERATOR_JWT" >"$ROOT_DIR/.operator-jwt"
echo "Operator JWT saved"

# Extract system account - check both possible locations
SYSTEM_ACCOUNT_JWT=$(echo "$EXPORT_RESPONSE" | jq -r '.system_account.jwt // .system_account // empty')
SYSTEM_ACCOUNT_SEED=$(echo "$EXPORT_RESPONSE" | jq -r '.system_account.seed // empty')

if [ ! -z "$SYSTEM_ACCOUNT_JWT" ] && [ "$SYSTEM_ACCOUNT_JWT" != "null" ] && [ ! -z "$SYSTEM_ACCOUNT_SEED" ] && [ "$SYSTEM_ACCOUNT_SEED" != "null" ]; then
  # Create a NATS credentials file format
  cat >"$ROOT_DIR/.system-account" <<EOF
-----BEGIN NATS USER JWT-----
$SYSTEM_ACCOUNT_JWT
------END NATS USER JWT------

************************* IMPORTANT *************************
NKEY Seed printed below can be used to sign and prove identity.
NKEYs are sensitive and should be treated as secrets.

-----BEGIN USER NKEY SEED-----
$SYSTEM_ACCOUNT_SEED
------END USER NKEY SEED------

*************************************************************
EOF
  echo "System account credentials saved"
else
  echo "No system account credentials available yet"
  touch "$ROOT_DIR/.system-account"
fi

# Get resolver preload configuration from the export
echo "Creating resolver configuration..."

# Extract accounts from the export response and create resolver preload
RESOLVER_PRELOAD="{}"
if echo "$EXPORT_RESPONSE" | jq -e '.accounts' >/dev/null 2>&1; then
  # Create resolver preload with account ID -> JWT mapping
  RESOLVER_PRELOAD=$(echo "$EXPORT_RESPONSE" | jq -c '
    .accounts | map({(.id): .jwt}) | add // {}
  ')

  # Also include system account if present
  if [ ! -z "$SYSTEM_ACCOUNT_JWT" ] && [ "$SYSTEM_ACCOUNT_JWT" != "null" ]; then
    SYSTEM_ACCOUNT_ID=$(echo "$EXPORT_RESPONSE" | jq -r '.system_account.id // empty')
    if [ ! -z "$SYSTEM_ACCOUNT_ID" ] && [ "$SYSTEM_ACCOUNT_ID" != "null" ]; then
      RESOLVER_PRELOAD=$(echo "$RESOLVER_PRELOAD" | jq --arg id "$SYSTEM_ACCOUNT_ID" --arg jwt "$SYSTEM_ACCOUNT_JWT" '. + {($id): $jwt}')
    fi
  fi
fi

# Save resolver preload in NATS config format
echo "$RESOLVER_PRELOAD" | jq -r 'to_entries | map("        \(.key): \(.value)") | join("\n")' >"$ROOT_DIR/.resolver-preload"
echo "Resolver preload configuration saved"

# Extract system account ID from JWT for Helm values
SYSTEM_ACCOUNT_ID_EXTRACTED=""
if [ ! -z "$SYSTEM_ACCOUNT_JWT" ] && [ "$SYSTEM_ACCOUNT_JWT" != "null" ]; then
  # Extract the 'sub' field from the JWT payload (the system account public key)
  PAYLOAD=$(echo "$SYSTEM_ACCOUNT_JWT" | awk -F. '{print $2}')
  # Add padding if needed for base64 decode
  while [ $((${#PAYLOAD} % 4)) -ne 0 ]; do PAYLOAD="${PAYLOAD}="; done
  SYSTEM_ACCOUNT_ID_EXTRACTED=$(echo "$PAYLOAD" | base64 -d 2>/dev/null | jq -r '.sub // empty' 2>/dev/null || echo "")
fi
echo "$SYSTEM_ACCOUNT_ID_EXTRACTED" >"$ROOT_DIR/.system-account-id"

echo ""
echo "=== NATS System Setup Complete ==="
echo "Team ID: $TEAM_ID"
echo "System ID: $SYSTEM_ID"
echo ""
echo "Configuration files created:"
echo "  - .operator-jwt"
echo "  - .system-account"
echo "  - .resolver-preload"
echo ""
echo "You can now run 'make apply' to deploy NATS"
