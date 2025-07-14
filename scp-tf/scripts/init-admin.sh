#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "=== Initializing SCP Admin User ==="

# Check required environment variables
if [ -z "$NAMESPACE" ]; then
  echo "ERROR: NAMESPACE environment variable must be set"
  exit 1
fi

# Wait for SCP to be ready
echo "Waiting for SCP to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=control-plane -n $NAMESPACE --timeout=300s || {
  echo "ERROR: SCP pods not ready after 300s"
  kubectl get pods -n $NAMESPACE
  exit 1
}

# Give SCP a moment to fully initialize
sleep 10

# Get the service name
SCP_SERVICE=$(kubectl get svc -n $NAMESPACE -l app.kubernetes.io/name=control-plane -o jsonpath='{.items[0].metadata.name}')
if [ -z "$SCP_SERVICE" ]; then
  echo "ERROR: Could not find SCP service"
  exit 1
fi

echo "Found SCP service: $SCP_SERVICE"

# Check if port 8080 is already in use
if lsof -Pi :8080 -sTCP:LISTEN -t >/dev/null 2>&1; then
  echo "Port 8080 is already in use, attempting to use existing connection..."
  PF_PID=""
else
  # Set up port forwarding
  echo "Setting up port forwarding..."
  kubectl port-forward -n $NAMESPACE svc/$SCP_SERVICE 8080:80 >/dev/null 2>&1 &
  PF_PID=$!
fi

# Function to cleanup on exit
cleanup() {
  local exit_code=$?
  echo "Cleaning up..."
  if [ ! -z "${PF_PID:-}" ]; then
    kill $PF_PID 2>/dev/null || true
  fi
  # Only propagate non-zero exit codes
  if [ $exit_code -ne 0 ]; then
    exit $exit_code
  fi
}
trap cleanup EXIT

# Give port forward time to establish
sleep 5

# Test connectivity with retries
echo "Testing SCP connectivity..."
MAX_RETRIES=5
RETRY_COUNT=0
while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:8080/ 2>/dev/null || echo "000")
  if [ "$HTTP_CODE" == "200" ] || [ "$HTTP_CODE" == "404" ]; then
    echo "SCP is responding (HTTP $HTTP_CODE)"
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "Connection attempt $RETRY_COUNT failed (HTTP $HTTP_CODE), retrying in 3 seconds..."
    sleep 3
  fi
done

if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
  echo "ERROR: Cannot connect to SCP at http://localhost:8080 after $MAX_RETRIES attempts"
  echo "Checking pod logs..."
  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=control-plane --tail=20
  exit 1
fi

# Check if admin user already exists
echo "Checking if admin user exists..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X GET "http://localhost:8080/api/core/beta/admin/app-user" \
  -H "accept: application/json" 2>/dev/null)

echo "HTTP Status: $HTTP_STATUS"

if [ "$HTTP_STATUS" == "204" ]; then
  echo "Admin user does not exist, creating..."

  # Generate a secure password
  ADMIN_PWD=$(openssl rand -base64 16)
  echo "Generated admin password: $ADMIN_PWD"

  # Create admin user
  CREATE_RESPONSE=$(curl -s -X POST "http://localhost:8080/api/core/beta/admin/app-user" \
    -H "accept: application/json" \
    -H "content-type: application/json" \
    -d "{\"generate_token\":true,\"password\":\"$ADMIN_PWD\",\"username\":\"admin\"}")

  if echo "$CREATE_RESPONSE" | grep -q "error"; then
    echo "ERROR: Failed to create admin user"
    echo "Response: $CREATE_RESPONSE"
    exit 1
  fi

  # Extract token if provided
  SCP_TOKEN=$(echo "$CREATE_RESPONSE" | jq -r '.token' 2>/dev/null || echo "")

  if [ -z "$SCP_TOKEN" ] || [ "$SCP_TOKEN" == "null" ]; then
    echo "ERROR: Failed to extract token from response"
    echo "Response: $CREATE_RESPONSE"
    exit 1
  fi

  echo "Admin user created successfully"
  echo "Token: $SCP_TOKEN"
elif [ "$HTTP_STATUS" == "403" ] || [ "$HTTP_STATUS" == "401" ]; then
  echo "Admin user already exists"
  # For existing admin user, we need the password
  ADMIN_PWD=""
  SCP_TOKEN=""
else
  echo "ERROR: Unexpected HTTP status: $HTTP_STATUS"
  echo "This might indicate the SCP API is not ready yet"
  exit 1
fi

# If we have a token from creation, we're done
if [ ! -z "$SCP_TOKEN" ] && [ "$SCP_TOKEN" != "null" ]; then
  echo "Using token from admin user creation"
else
  # For existing admin user, try to get the password
  if [ -z "$ADMIN_PWD" ]; then
    echo "Checking for saved admin password..."
    if [ -f "${SCRIPT_DIR}/../.admin-password" ]; then
      ADMIN_PWD=$(cat "${SCRIPT_DIR}/../.admin-password")
      echo "Using saved admin password"
    else
      echo "ERROR: Admin user exists but no password found"
      echo "Please save the admin password in .admin-password file"
      exit 1
    fi
  fi

  # Try to login to get a token
  echo "Attempting to login to get API token..."
  # Try various login endpoints
  for LOGIN_ENDPOINT in "/api/core/v1/auth/login" "/api/v1/auth/login" "/api/auth/login"; do
    echo "Trying login endpoint: $LOGIN_ENDPOINT"
    RESPONSE=$(curl -s -X POST "http://localhost:8080$LOGIN_ENDPOINT" \
      -H "Content-Type: application/json" \
      -d "{\"username\":\"admin\",\"password\":\"$ADMIN_PWD\"}" 2>/dev/null)

    # Extract token
    SCP_TOKEN=$(echo "$RESPONSE" | jq -r '.token' 2>/dev/null || echo "")

    if [ ! -z "$SCP_TOKEN" ] && [ "$SCP_TOKEN" != "null" ]; then
      echo "API token obtained successfully"
      break
    fi
  done

  if [ -z "$SCP_TOKEN" ] || [ "$SCP_TOKEN" == "null" ]; then
    echo "WARN: Could not get API token through login"
    echo "The API token can be generated through the web UI"
    # Don't exit, still save the password
  fi
fi

# Save credentials to files
echo "Saving credentials..."
if [ ! -z "$ADMIN_PWD" ]; then
  echo "$ADMIN_PWD" > "${SCRIPT_DIR}/../.admin-password"
  echo "Admin password saved to .admin-password"
fi

if [ ! -z "$SCP_TOKEN" ] && [ "$SCP_TOKEN" != "null" ]; then
  echo "$SCP_TOKEN" > "${SCRIPT_DIR}/../.api-token"
  echo "API token saved to .api-token"
else
  echo "WARN: No API token available to save"
fi

# If requested, create demo team and project
if [ "$CREATE_DEMO_TEAM" == "true" ] && [ ! -z "$SCP_TOKEN" ] && [ "$SCP_TOKEN" != "null" ]; then
  echo "Creating demo team..."

  # Try different API endpoints for team creation
  TEAM_CREATED=false
  for TEAMS_ENDPOINT in "/api/v1/teams" "/api/core/v1/teams" "/api/core/beta/teams"; do
    echo "Trying teams endpoint: $TEAMS_ENDPOINT"
    TEAM_RESPONSE=$(curl -s -X POST "http://localhost:8080$TEAMS_ENDPOINT" \
      -H "Authorization: Bearer $SCP_TOKEN" \
      -H "Content-Type: application/json" \
      -d '{"name":"demo-team"}' 2>/dev/null || true)

    TEAM_ID=$(echo "$TEAM_RESPONSE" | jq -r '.id' 2>/dev/null || echo "")

    if [ ! -z "$TEAM_ID" ] && [ "$TEAM_ID" != "null" ] && [ "$TEAM_ID" != "" ]; then
      TEAM_CREATED=true
      echo "Demo team created with ID: $TEAM_ID"

      # Create project
      echo "Creating demo project..."
      PROJECT_RESPONSE=$(curl -s -X POST "http://localhost:8080$TEAMS_ENDPOINT/$TEAM_ID/projects" \
        -H "Authorization: Bearer $SCP_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{"name":"demo-project","description":"Demo Project"}' 2>/dev/null || true)

      PROJECT_ID=$(echo "$PROJECT_RESPONSE" | jq -r '.id' 2>/dev/null || echo "")

      if [ ! -z "$PROJECT_ID" ] && [ "$PROJECT_ID" != "null" ] && [ "$PROJECT_ID" != "" ]; then
        echo "Demo project created with ID: $PROJECT_ID"
        echo "$TEAM_ID" > "${SCRIPT_DIR}/../.team-id"
        echo "$PROJECT_ID" > "${SCRIPT_DIR}/../.project-id"
      else
        echo "WARNING: Failed to create demo project"
        echo "Response: $PROJECT_RESPONSE"
      fi
      break
    fi
  done

  if [ "$TEAM_CREATED" != "true" ]; then
    echo "WARNING: Failed to create demo team with any endpoint"
    echo "Last response: $TEAM_RESPONSE"
  fi
elif [ "$CREATE_DEMO_TEAM" == "true" ]; then
  echo "Skipping demo team creation - no API token available"
fi

# Ensure we exit cleanly
echo "=== SCP initialization complete! ==="
echo ""
if [ -f "${SCRIPT_DIR}/../.admin-password" ]; then
  echo "Admin credentials saved:"
  echo "  Username: admin"
  echo "  Password: Saved in .admin-password"
fi
if [ -f "${SCRIPT_DIR}/../.api-token" ]; then
  echo "  API Token: Saved in .api-token"
else
  echo "  API Token: Not available (generate through web UI if needed)"
fi
echo ""
echo "Access the SCP UI:"
echo "  Run: make port-forward"
echo "  URL: http://localhost:30080"

# Exit successfully
exit 0