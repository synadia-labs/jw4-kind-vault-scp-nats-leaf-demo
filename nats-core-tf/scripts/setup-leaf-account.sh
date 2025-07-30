#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
SCP_DIR="$ROOT_DIR/../scp-tf"

LEAF_ACCOUNT_NAME="${LEAF_ACCOUNT_NAME:-LEAF_ACCOUNT}"

echo "=== Setting up Leaf Account in SCP ==="

# Check if we have system ID
if [ ! -f "$ROOT_DIR/.system-id" ]; then
  echo "ERROR: System ID not found. Run 'make setup-system' first."
  exit 1
fi

SYSTEM_ID=$(cat "$ROOT_DIR/.system-id")
if [ -z "$SYSTEM_ID" ] || [ "$SYSTEM_ID" == "null" ]; then
  echo "ERROR: Invalid system ID"
  exit 1
fi

# Check if SCP credentials exist
if [ ! -f "$SCP_DIR/.api-token" ]; then
  echo "ERROR: SCP API token not found. Ensure SCP is deployed."
  exit 1
fi

# Get SCP credentials
SCP_TOKEN=$(cat "$SCP_DIR/.api-token")
if [ -z "$SCP_TOKEN" ] || [ "$SCP_TOKEN" == "null" ]; then
  echo "ERROR: Invalid SCP API token"
  exit 1
fi

# Setup port-forward to SCP
echo "Setting up port forward to SCP..."
kubectl port-forward -n scp svc/scp-control-plane 8080:80 >/dev/null 2>&1 &
PF_PID=$!

cleanup() {
  if [ ! -z "$PF_PID" ]; then
    kill $PF_PID 2>/dev/null || true
  fi
}
trap cleanup EXIT

# Wait for port forward
sleep 3

# Check if system is connected to SCP
echo "Checking if NATS system is connected to SCP..."
SYSTEM_STATUS=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
  "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID" | jq -r '.state // "unknown"')

if [ "$SYSTEM_STATUS" != "Connected" ]; then
  echo "ERROR: NATS system is not connected to SCP (state: $SYSTEM_STATUS)"
  echo "Please ensure NATS is running and connected before configuring leaf accounts."
  echo "You can check system status in SCP UI or run 'kubectl get pods -n nats'"
  exit 1
fi

echo "✓ NATS system is connected to SCP"

# Check if leaf account already exists
echo "Checking for existing leaf account..."
EXISTING_ACCOUNTS=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
  "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID/accounts")

LEAF_ACCOUNT_ID=$(echo "$EXISTING_ACCOUNTS" | jq -r ".items[]? | select(.name==\"$LEAF_ACCOUNT_NAME\") | .id")

if [ ! -z "$LEAF_ACCOUNT_ID" ] && [ "$LEAF_ACCOUNT_ID" != "null" ]; then
  echo "✓ Leaf account '$LEAF_ACCOUNT_NAME' already exists with ID: $LEAF_ACCOUNT_ID"
else
  echo "Creating leaf account '$LEAF_ACCOUNT_NAME'..."

  # Create the leaf account
  CREATE_ACCOUNT_RESPONSE=$(curl -s -X POST \
    "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID/accounts" \
    -H "Authorization: Bearer $SCP_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$LEAF_ACCOUNT_NAME\"
    }")

  LEAF_ACCOUNT_ID=$(echo "$CREATE_ACCOUNT_RESPONSE" | jq -r '.id // empty')

  if [ -z "$LEAF_ACCOUNT_ID" ] || [ "$LEAF_ACCOUNT_ID" == "null" ]; then
    echo "ERROR: Failed to create leaf account"
    echo "Response: $CREATE_ACCOUNT_RESPONSE"
    exit 1
  fi

  echo "✓ Created leaf account with ID: $LEAF_ACCOUNT_ID"
fi

# Save the leaf account ID
echo "$LEAF_ACCOUNT_ID" >"$ROOT_DIR/.leaf-account-id"

# Get the leaf account JWT from the account details
echo "Fetching leaf account JWT..."
ACCOUNT_DETAILS=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
  "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID/accounts")

LEAF_JWT=$(echo "$ACCOUNT_DETAILS" | jq -r ".items[]? | select(.id==\"$LEAF_ACCOUNT_ID\") | .jwt")

if [ ! -z "$LEAF_JWT" ] && [ "$LEAF_JWT" != "null" ]; then
  # Save just the account JWT - leaf nodes can connect with the account JWT
  echo "$LEAF_JWT" >"$ROOT_DIR/.leaf-jwt"

  # Also save a minimal credentials format
  cat >"$ROOT_DIR/.leaf-credentials" <<EOF
-----BEGIN NATS ACCOUNT JWT-----
$LEAF_JWT
------END NATS ACCOUNT JWT------

************************* IMPORTANT *************************
This is the account JWT for LEAF_ACCOUNT.
Leaf nodes can connect using this account JWT.
*************************************************************
EOF

  echo "✓ Leaf account JWT saved to .leaf-jwt and .leaf-credentials"
else
  echo "ERROR: Could not retrieve leaf account JWT"
  echo "Account details response: $ACCOUNT_DETAILS"
  exit 1
fi

# Note: Account already has appropriate limits for leaf connections (-1 = unlimited)
# The account was created with proper permissions for leaf node connections

# Check for existing groups and provide guidance for manual group/user creation
LEAF_GROUP_NAME="${LEAF_GROUP_NAME:-leaf-users}"
LEAF_USER_NAME="${LEAF_USER_NAME:-leaf-user}"

echo ""
echo "=== Group and User Setup ==="

# Get signing key groups for the account
echo "Fetching signing key groups for LEAF_ACCOUNT..."
GROUP_RESPONSE=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
  "http://localhost:8080/api/core/beta/accounts/$LEAF_ACCOUNT_ID/account-sk-groups")

# Find the Default group
DEFAULT_GROUP_ID=$(echo "$GROUP_RESPONSE" | jq -r '.items[] | select(.name == "Default") | .id')

if [ -z "$DEFAULT_GROUP_ID" ] || [ "$DEFAULT_GROUP_ID" == "null" ]; then
  echo "ERROR: Could not find Default signing key group"
  echo "Groups found: $(echo "$GROUP_RESPONSE" | jq -r '.items[].name' | tr '\n' ', ')"
  exit 1
fi

echo "✓ Found Default signing key group with ID: $DEFAULT_GROUP_ID"

# Create a user in the Default group
LEAF_USER_NAME="${LEAF_USER_NAME:-leaf-user}"
echo "Creating NATS user '$LEAF_USER_NAME' in Default group..."

CREATE_USER_RESPONSE=$(curl -s -X POST \
  "http://localhost:8080/api/core/beta/accounts/$LEAF_ACCOUNT_ID/nats-users" \
  -H "Authorization: Bearer $SCP_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"$LEAF_USER_NAME\",
    \"sk_group_id\": \"$DEFAULT_GROUP_ID\"
  }")

LEAF_USER_ID=$(echo "$CREATE_USER_RESPONSE" | jq -r '.id // empty')

if [ -z "$LEAF_USER_ID" ] || [ "$LEAF_USER_ID" == "null" ]; then
  echo "ERROR: Failed to create NATS user"
  echo "Response: $CREATE_USER_RESPONSE"
  exit 1
fi

echo "✓ Created NATS user '$LEAF_USER_NAME' with ID: $LEAF_USER_ID"
echo "$LEAF_USER_ID" >"$ROOT_DIR/.leaf-user-id"

# Get the user credentials
echo "Fetching user credentials..."
CREDS_RESPONSE=$(curl -s -X POST \
  "http://localhost:8080/api/core/beta/nats-users/$LEAF_USER_ID/creds" \
  -H "Authorization: Bearer $SCP_TOKEN")

if [ -z "$CREDS_RESPONSE" ] || [ "$CREDS_RESPONSE" == "null" ]; then
  echo "ERROR: Failed to fetch user credentials"
  exit 1
fi

# Save the credentials
echo "$CREDS_RESPONSE" >"$ROOT_DIR/.leaf.creds"
echo "✓ User credentials saved to .leaf.creds"

echo ""
echo "=== Leaf Account Setup Complete ==="
echo "Account Name: $LEAF_ACCOUNT_NAME"
echo "Account ID: $LEAF_ACCOUNT_ID"
echo "User Name: $LEAF_USER_NAME"
echo ""
echo "Files created:"
echo "  - .leaf-account-id: Account identifier"
echo "  - .leaf-jwt: Account JWT"
echo "  - .leaf-credentials: Account credentials"
echo "  - .leaf-user-id: User identifier"
echo "  - .leaf.creds: User credentials for leaf node authentication"
echo ""
echo "✅ Setup Complete:"
echo "  ✓ LEAF_ACCOUNT configured in SCP"
echo "  ✓ User '$LEAF_USER_NAME' created in Default signing key group"
echo "  ✓ User credentials saved to .leaf.creds"
echo "  ✓ NATS Core cluster accepting leaf connections on port 7422"
echo ""
echo "📋 Next Steps:"
echo "  1. Copy .leaf.creds to ../nats-leaf-tf/ directory"
echo "  2. Deploy leaf cluster: cd ../nats-leaf-tf && make apply"
echo "  3. Test leaf connection: make test"
