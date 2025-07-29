#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR="$SCRIPT_DIR/.."
SCP_DIR="$ROOT_DIR/../scp-tf"

echo "=== Cleaning up NATS System from SCP ==="

# Check if we have system ID
if [ ! -f "$ROOT_DIR/.system-id" ]; then
  echo "No system ID found - nothing to clean up"
  exit 0
fi

SYSTEM_ID=$(cat "$ROOT_DIR/.system-id")
if [ -z "$SYSTEM_ID" ] || [ "$SYSTEM_ID" == "null" ]; then
  echo "Invalid system ID - nothing to clean up"
  exit 0
fi

# Check if SCP credentials exist
if [ ! -f "$SCP_DIR/.api-token" ]; then
  echo "WARNING: SCP API token not found - cannot clean up system from SCP"
  echo "System ID $SYSTEM_ID may remain in SCP"
  exit 0
fi

# Get SCP credentials
SCP_TOKEN=$(cat "$SCP_DIR/.api-token")
if [ -z "$SCP_TOKEN" ] || [ "$SCP_TOKEN" == "null" ]; then
  echo "WARNING: Invalid SCP API token - cannot clean up system from SCP"
  exit 0
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

# Get team ID from system before deletion
echo "Getting team information from system..."
SYSTEM_INFO=$(curl -s -H "Authorization: Bearer $SCP_TOKEN" \
  "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID" 2>/dev/null || echo '{}')

TEAM_ID=$(echo "$SYSTEM_INFO" | jq -r '.team.id // empty' 2>/dev/null)
TEAM_NAME=$(echo "$SYSTEM_INFO" | jq -r '.team.name // empty' 2>/dev/null)

# Try to delete the system
echo "Deleting system $SYSTEM_ID from SCP..."
DELETE_RESPONSE=$(curl -s -X DELETE "http://localhost:8080/api/core/beta/systems/$SYSTEM_ID" \
  -H "Authorization: Bearer $SCP_TOKEN" \
  -w "HTTP_STATUS:%{http_code}")

HTTP_STATUS=$(echo "$DELETE_RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
RESPONSE_BODY=$(echo "$DELETE_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//')

if [ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "204" ]; then
  echo "✓ System successfully deleted from SCP"
elif [ "$HTTP_STATUS" = "404" ]; then
  echo "✓ System not found in SCP (already deleted)"
else
  echo "WARNING: Failed to delete system from SCP (HTTP $HTTP_STATUS)"
  if [ ! -z "$RESPONSE_BODY" ]; then
    echo "Response: $RESPONSE_BODY"
  fi
  echo ""
  echo "MANUAL CLEANUP REQUIRED:"
  echo "1. Open SCP UI: kubectl port-forward -n scp svc/scp-control-plane 8080:80"
  echo "2. Navigate to http://localhost:8080"
  echo "3. Go to Systems and manually delete system: $SYSTEM_ID"
  echo "4. Or use SCP CLI if available to unmanage/delete the system"
fi

# Try to delete the team if we have team info and system deletion was successful
if [ ! -z "$TEAM_ID" ] && [ ! -z "$TEAM_NAME" ] && ([ "$HTTP_STATUS" = "200" ] || [ "$HTTP_STATUS" = "204" ] || [ "$HTTP_STATUS" = "404" ]); then
  echo ""
  echo "Deleting team '$TEAM_NAME' (ID: $TEAM_ID) from SCP..."
  
  TEAM_DELETE_RESPONSE=$(curl -s -X DELETE "http://localhost:8080/api/core/beta/teams/$TEAM_ID" \
    -H "Authorization: Bearer $SCP_TOKEN" \
    -w "HTTP_STATUS:%{http_code}")

  TEAM_HTTP_STATUS=$(echo "$TEAM_DELETE_RESPONSE" | grep -o "HTTP_STATUS:[0-9]*" | cut -d: -f2)
  TEAM_RESPONSE_BODY=$(echo "$TEAM_DELETE_RESPONSE" | sed 's/HTTP_STATUS:[0-9]*$//')

  if [ "$TEAM_HTTP_STATUS" = "200" ] || [ "$TEAM_HTTP_STATUS" = "204" ]; then
    echo "✓ Team '$TEAM_NAME' successfully deleted from SCP"
  elif [ "$TEAM_HTTP_STATUS" = "404" ]; then
    echo "✓ Team '$TEAM_NAME' not found in SCP (already deleted)"
  else
    echo "WARNING: Failed to delete team '$TEAM_NAME' from SCP (HTTP $TEAM_HTTP_STATUS)"
    if [ ! -z "$TEAM_RESPONSE_BODY" ]; then
      echo "Response: $TEAM_RESPONSE_BODY"
    fi
    echo ""
    echo "MANUAL TEAM CLEANUP REQUIRED:"
    echo "1. Open SCP UI: kubectl port-forward -n scp svc/scp-control-plane 8080:80"
    echo "2. Navigate to http://localhost:8080"
    echo "3. Go to Teams and manually delete team: $TEAM_NAME (ID: $TEAM_ID)"
  fi
elif [ ! -z "$TEAM_ID" ]; then
  echo ""
  echo "WARNING: Cannot delete team '$TEAM_NAME' because system deletion failed"
  echo "Team ID: $TEAM_ID"
fi

echo ""
echo "=== SCP Cleanup Complete ==="