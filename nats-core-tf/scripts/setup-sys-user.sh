#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$SCRIPT_DIR/.."
SCP_DIR="$ROOT_DIR/../scp-tf"

SYS_USER_NAME="${SYS_USER_NAME:-sys-user}"

echo "=== Setting up System User in SYS Account ==="

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

# Check if we have system account JWT public key
if [ ! -f "$ROOT_DIR/.system-account-id" ]; then
  echo "ERROR: System account ID not found. Run 'make setup-system' first."
  exit 1
fi

SYSTEM_ACCOUNT_JWT_SUB=$(cat "$ROOT_DIR/.system-account-id")
if [ -z "$SYSTEM_ACCOUNT_JWT_SUB" ] || [ "$SYSTEM_ACCOUNT_JWT_SUB" == "null" ]; then
  echo "ERROR: Invalid system account JWT subject"
  exit 1
fi

echo "✓ System account JWT subject: $SYSTEM_ACCOUNT_JWT_SUB"

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
  echo "Please ensure NATS is running and connected before creating system user."
  echo "You can check system status in SCP UI or run 'kubectl get pods -n nats'"
  exit 1
fi

echo "✓ NATS system is connected to SCP"

# Get the SYS account details
echo "Fetching SYS account details..."
ACCOUNTS_RESPONSE=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
  "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID/accounts")

# Find the SYS account by name (should be "SYS") or by JWT subject
SYS_ACCOUNT_DATA=$(echo "$ACCOUNTS_RESPONSE" | jq -r ".items[]? | select(.name==\"SYS\")")

if [ -z "$SYS_ACCOUNT_DATA" ] || [ "$SYS_ACCOUNT_DATA" == "null" ]; then
  # Try to find by JWT subject if name doesn't work
  for account in $(echo "$ACCOUNTS_RESPONSE" | jq -r '.items[]? | @base64'); do
    _jq() {
      echo ${account} | base64 --decode | jq -r ${1}
    }
    
    account_jwt=$(_jq '.jwt')
    if [ ! -z "$account_jwt" ] && [ "$account_jwt" != "null" ]; then
      # Extract the 'sub' field from the JWT
      payload=$(echo "$account_jwt" | awk -F. '{print $2}')
      # Add padding if needed for base64 decode
      while [ $((${#payload} % 4)) -ne 0 ]; do payload="${payload}="; done
      jwt_sub=$(echo "$payload" | base64 -d 2>/dev/null | jq -r '.sub // empty' 2>/dev/null || echo "")
      
      if [ "$jwt_sub" == "$SYSTEM_ACCOUNT_JWT_SUB" ]; then
        SYS_ACCOUNT_DATA=$(echo ${account} | base64 --decode)
        break
      fi
    fi
  done
fi

if [ -z "$SYS_ACCOUNT_DATA" ] || [ "$SYS_ACCOUNT_DATA" == "null" ]; then
  echo "ERROR: Could not find SYS account with JWT subject: $SYSTEM_ACCOUNT_JWT_SUB"
  echo "Available accounts:"
  echo "$ACCOUNTS_RESPONSE" | jq -r '.items[]? | "\(.name) - \(.id)"'
  exit 1
fi

SYSTEM_ACCOUNT_ID=$(echo "$SYS_ACCOUNT_DATA" | jq -r '.id')
SYS_ACCOUNT_NAME=$(echo "$SYS_ACCOUNT_DATA" | jq -r '.name')
echo "✓ Found SYS account '$SYS_ACCOUNT_NAME' with ID: $SYSTEM_ACCOUNT_ID"

# Get signing key groups for the SYS account
echo "Fetching signing key groups for SYS account..."
GROUP_RESPONSE=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
  "http://localhost:8080/api/core/beta/accounts/$SYSTEM_ACCOUNT_ID/account-sk-groups")

# Find the Default group
DEFAULT_GROUP_ID=$(echo "$GROUP_RESPONSE" | jq -r '.items[] | select(.name == "Default") | .id')

if [ -z "$DEFAULT_GROUP_ID" ] || [ "$DEFAULT_GROUP_ID" == "null" ]; then
  echo "ERROR: Could not find Default signing key group in SYS account"
  echo "Groups found: $(echo "$GROUP_RESPONSE" | jq -r '.items[].name' | tr '\n' ', ')"
  exit 1
fi

echo "✓ Found Default signing key group with ID: $DEFAULT_GROUP_ID"

# Check if user already exists
echo "Checking for existing system user..."
EXISTING_USERS=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
  "http://localhost:8080/api/core/beta/accounts/$SYSTEM_ACCOUNT_ID/nats-users")

SYS_USER_ID=$(echo "$EXISTING_USERS" | jq -r ".items[]? | select(.name==\"$SYS_USER_NAME\") | .id")

if [ ! -z "$SYS_USER_ID" ] && [ "$SYS_USER_ID" != "null" ]; then
  echo "✓ System user '$SYS_USER_NAME' already exists with ID: $SYS_USER_ID"
else
  # Create a user in the Default group
  echo "Creating NATS system user '$SYS_USER_NAME' in Default group..."

  CREATE_USER_RESPONSE=$(curl -s -X POST \
    "http://localhost:8080/api/core/beta/accounts/$SYSTEM_ACCOUNT_ID/nats-users" \
    -H "Authorization: Bearer $SCP_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{
      \"name\": \"$SYS_USER_NAME\",
      \"sk_group_id\": \"$DEFAULT_GROUP_ID\"
    }")

  SYS_USER_ID=$(echo "$CREATE_USER_RESPONSE" | jq -r '.id // empty')

  if [ -z "$SYS_USER_ID" ] || [ "$SYS_USER_ID" == "null" ]; then
    echo "ERROR: Failed to create NATS system user"
    echo "Response: $CREATE_USER_RESPONSE"
    exit 1
  fi

  echo "✓ Created NATS system user '$SYS_USER_NAME' with ID: $SYS_USER_ID"
fi

echo "$SYS_USER_ID" >"$ROOT_DIR/.sys-user-id"

# Get the user credentials
echo "Fetching system user credentials..."
CREDS_RESPONSE=$(curl -s -X POST \
  "http://localhost:8080/api/core/beta/nats-users/$SYS_USER_ID/creds" \
  -H "Authorization: Bearer $SCP_TOKEN")

if [ -z "$CREDS_RESPONSE" ] || [ "$CREDS_RESPONSE" == "null" ]; then
  echo "ERROR: Failed to fetch system user credentials"
  exit 1
fi

# Save the credentials
echo "$CREDS_RESPONSE" >"$ROOT_DIR/.sys-user.creds"
echo "✓ System user credentials saved to .sys-user.creds"

# Also save the system account JWT for reference
SYS_JWT=$(echo "$SYS_ACCOUNT_DATA" | jq -r '.jwt')
if [ ! -z "$SYS_JWT" ] && [ "$SYS_JWT" != "null" ]; then
  echo "$SYS_JWT" >"$ROOT_DIR/.sys-jwt"
  echo "✓ System account JWT saved to .sys-jwt"
fi

echo ""
echo "=== System User Setup Complete ==="
echo "Account Name: $SYS_ACCOUNT_NAME"
echo "Account ID: $SYSTEM_ACCOUNT_ID"
echo "User Name: $SYS_USER_NAME"
echo "User ID: $SYS_USER_ID"
echo ""
echo "Files created:"
echo "  - .sys-user-id: System user identifier"
echo "  - .sys-user.creds: System user credentials for authentication"
echo "  - .sys-jwt: System account JWT"
echo ""
echo "✅ Setup Complete:"
echo "  ✓ System user '$SYS_USER_NAME' created in SYS account"
echo "  ✓ User credentials saved to .sys-user.creds"
echo "  ✓ Can be used for NATS monitoring and management operations"
echo ""
echo "📋 Usage Example:"
echo "  nats --creds .sys-user.creds --server nats://localhost:4222 server check connection"
echo "  nats --creds .sys-user.creds --server nats://localhost:4222 server report jetstream"