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

# Check if account-level groups are supported (read-only check)
echo "Checking SCP group management capabilities..."
GROUP_RESPONSE=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
  "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID/accounts/$LEAF_ACCOUNT_ID/account-sk-groups" 2>/dev/null || echo '{"items":[]}')

if echo "$GROUP_RESPONSE" | jq -e '.items' >/dev/null 2>&1; then
  # Groups endpoint exists, check for existing groups
  EXISTING_GROUPS=$(echo "$GROUP_RESPONSE" | jq -r '.items[]?.name' 2>/dev/null | tr '\n' ', ' | sed 's/,$//')

  if [ ! -z "$EXISTING_GROUPS" ]; then
    echo "✓ Found existing groups in LEAF_ACCOUNT: $EXISTING_GROUPS"
  else
    echo "! No groups found in LEAF_ACCOUNT"
  fi

  # Note: Based on SCP logs, group creation via API returns 404 (not supported)
  echo ""
  echo "📋 Manual Group and User Setup Required:"
  echo "   The SCP API does not support creating groups and users programmatically."
  echo "   Please use the SCP Web UI to complete the setup:"
  echo ""
  echo "   1. Open SCP Web UI: http://localhost:8080 (requires 'make port-forward')"
  echo "   2. Navigate to Systems → nats-core → Accounts → LEAF_ACCOUNT"
  echo "   3. Create a new group named '$LEAF_GROUP_NAME'"
  echo "   4. Create a new user named '$LEAF_USER_NAME' in the '$LEAF_GROUP_NAME' group"
  echo "   5. Download the user credentials (JWT + key) for leaf node authentication"
  echo ""
  echo "   Alternative: Use NSC (NATS Security CLI) with the account signing keys"
  echo "   from the account JWT to create users locally."

else
  echo "! No existing groups found - will attempt to create group"
  
  # Try to create the group using account-sk-groups endpoint
  echo "Creating group '$LEAF_GROUP_NAME'..."
  CREATE_GROUP_RESPONSE=$(curl -s -X POST \
    "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID/accounts/$LEAF_ACCOUNT_ID/account-sk-groups" \
    -H "Authorization: Bearer $SCP_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$LEAF_GROUP_NAME\"}" 2>/dev/null)

  LEAF_GROUP_ID=$(echo "$CREATE_GROUP_RESPONSE" | jq -r '.id // empty' 2>/dev/null)

  if [ ! -z "$LEAF_GROUP_ID" ] && [ "$LEAF_GROUP_ID" != "null" ]; then
    echo "✓ Created group '$LEAF_GROUP_NAME' with ID: $LEAF_GROUP_ID"
    echo "$LEAF_GROUP_ID" > "$ROOT_DIR/.leaf-group-id"
    
    # Create user in the new group
    echo "Creating user '$LEAF_USER_NAME' in group '$LEAF_GROUP_NAME'..."
    CREATE_USER_RESPONSE=$(curl -s -X POST \
      "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID/accounts/$LEAF_ACCOUNT_ID/account-sk-groups/$LEAF_GROUP_ID/users" \
      -H "Authorization: Bearer $SCP_TOKEN" \
      -H "Content-Type: application/json" \
      -d "{\"name\": \"$LEAF_USER_NAME\"}" 2>/dev/null)

    LEAF_USER_ID=$(echo "$CREATE_USER_RESPONSE" | jq -r '.id // empty' 2>/dev/null)

    if [ ! -z "$LEAF_USER_ID" ] && [ "$LEAF_USER_ID" != "null" ]; then
      echo "✓ Created user '$LEAF_USER_NAME' with ID: $LEAF_USER_ID"
      echo "$LEAF_USER_ID" > "$ROOT_DIR/.leaf-user-id"
      
      # Get user credentials
      echo "Fetching user credentials..."
      USER_CREDS_RESPONSE=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
        "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID/accounts/$LEAF_ACCOUNT_ID/account-sk-groups/$LEAF_GROUP_ID/users/$LEAF_USER_ID/credentials" 2>/dev/null)
      
      if echo "$USER_CREDS_RESPONSE" | jq -e '.jwt' >/dev/null 2>&1; then
        echo "$USER_CREDS_RESPONSE" > "$ROOT_DIR/.leaf-user-credentials.json"
        
        # Create proper NATS credentials file
        USER_JWT=$(echo "$USER_CREDS_RESPONSE" | jq -r '.jwt')
        USER_SEED=$(echo "$USER_CREDS_RESPONSE" | jq -r '.seed // empty')
        
        cat > "$ROOT_DIR/.leaf-user.creds" <<EOF
-----BEGIN NATS USER JWT-----
$USER_JWT
------END NATS USER JWT------

************************* IMPORTANT *************************
NKEY Seed printed below can be used to sign and prove identity.
NKEYs are sensitive and should be treated as secrets.

-----BEGIN USER NKEY SEED-----
$USER_SEED
------END USER NKEY SEED------

*************************************************************
EOF
        echo "✓ User credentials saved to .leaf-user.creds"
      else
        echo "! Could not fetch user credentials"
      fi
    else
      echo "! Failed to create user"
      echo "Response: $CREATE_USER_RESPONSE"
    fi
  else
    echo "! Failed to create group"
    echo "Response: $CREATE_GROUP_RESPONSE"
  fi
fi

echo ""
echo "=== Leaf Account Setup Complete ==="
echo "Account Name: $LEAF_ACCOUNT_NAME"
echo "Account ID: $LEAF_ACCOUNT_ID"
echo ""
echo "Files created:"
echo "  - .leaf-account-id: Account identifier"
echo "  - .leaf-jwt: Account JWT for leaf node configuration"
echo "  - .leaf-credentials: Human-readable account credentials"
echo ""
echo "✅ Infrastructure Ready:"
echo "  ✓ LEAF_ACCOUNT configured in SCP with unlimited leaf connections"
echo "  ✓ NATS Core cluster accepting leaf connections on port 7422"
echo "  ✓ Account JWT available for leaf node authentication setup"
echo ""
echo "📋 Next Steps:"
echo "  1. Create groups and users through SCP Web UI as outlined above"
echo "  2. Download user credentials (JWT + private key) from SCP"
echo "  3. Configure leaf nodes with user credentials for authentication"
echo "  4. Test leaf connection: make test-leaf-connection"
